-- =============================================================================
-- init_db.sql — Schéma PostgreSQL pour le POC Gmail Automation
-- Exécuté automatiquement au premier démarrage du container PostgreSQL
-- =============================================================================

-- Extension pour les timestamps automatiques
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- Table principale : traitement des emails
-- =============================================================================
CREATE TABLE IF NOT EXISTS email_processing (
    id                    SERIAL PRIMARY KEY,
    gmail_message_id      VARCHAR(255) NOT NULL UNIQUE,
    thread_id             VARCHAR(255),
    message_id_header     VARCHAR(512),

    -- Métadonnées email
    from_email            VARCHAR(512),
    from_name             VARCHAR(255),
    reply_to              VARCHAR(512),
    subject               TEXT,
    received_at           TIMESTAMP WITH TIME ZONE,
    snippet               TEXT,

    -- État du traitement
    state                 VARCHAR(50) DEFAULT 'NEW'
                            CHECK (state IN (
                              'NEW', 'ANALYZING', 'ANALYZED',
                              'RISK_REVIEW', 'NEEDS_REPLY',
                              'DRAFT_READY', 'AWAITING_APPROVAL',
                              'SENT', 'ARCHIVED', 'ESCALATED',
                              'IGNORED', 'SPAM', 'ERROR',
                              'ALREADY_PROCESSED'
                            )),

    -- Scoring sécurité
    risk_level            VARCHAR(10) CHECK (risk_level IN ('LOW', 'MED', 'HIGH')),
    risk_score            INTEGER CHECK (risk_score >= 0 AND risk_score <= 100),
    risk_reasons          JSONB DEFAULT '[]'::jsonb,
    block_send            BOOLEAN DEFAULT FALSE,
    attachments_risk      VARCHAR(20) DEFAULT 'none',

    -- Analyse LLM
    priority              VARCHAR(5) CHECK (priority IN ('P1', 'P2', 'P3')),
    category              VARCHAR(50) CHECK (category IN (
                            'CLIENT', 'BILLING', 'INCIDENT',
                            'ADMIN', 'HR', 'SPAM', 'OTHER'
                          )),
    needs_reply           BOOLEAN DEFAULT FALSE,
    recommended_action    VARCHAR(50) CHECK (recommended_action IN (
                            'DRAFT_REPLY', 'ARCHIVE', 'FOLLOW_UP',
                            'ESCALATE', 'IGNORE', NULL
                          )),
    llm_summary           TEXT,
    llm_confidence        DECIMAL(3,2) CHECK (llm_confidence >= 0 AND llm_confidence <= 1),
    llm_response          JSONB,
    llm_parse_error       TEXT,
    llm_fallback_used     BOOLEAN DEFAULT FALSE,

    -- Draft Gmail
    draft_id              VARCHAR(255),
    draft_subject         TEXT,
    draft_body_preview    TEXT,  -- 500 premiers caractères

    -- Interaction Telegram
    telegram_message_id   BIGINT,
    operator_action       VARCHAR(50) CHECK (operator_action IN (
                            'APPROVE_SEND', 'EDIT_DRAFT', 'SAVE_DRAFT_ONLY',
                            'APPLY_LABEL', 'ARCHIVE', 'MARK_SPAM',
                            'ESCALATE', 'IGNORE', NULL
                          )),
    operator_telegram_id  BIGINT,
    operator_action_at    TIMESTAMP WITH TIME ZONE,

    -- Contexte
    is_vip                BOOLEAN DEFAULT FALSE,
    is_internal           BOOLEAN DEFAULT FALSE,
    is_demo               BOOLEAN DEFAULT FALSE,
    run_id                VARCHAR(50),  -- ID de l'exécution n8n

    -- Timestamps
    created_at            TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at            TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index pour les requêtes fréquentes
CREATE INDEX IF NOT EXISTS idx_ep_gmail_msg_id  ON email_processing(gmail_message_id);
CREATE INDEX IF NOT EXISTS idx_ep_thread_id     ON email_processing(thread_id);
CREATE INDEX IF NOT EXISTS idx_ep_state         ON email_processing(state);
CREATE INDEX IF NOT EXISTS idx_ep_priority      ON email_processing(priority);
CREATE INDEX IF NOT EXISTS idx_ep_risk_level    ON email_processing(risk_level);
CREATE INDEX IF NOT EXISTS idx_ep_created_at    ON email_processing(created_at);
CREATE INDEX IF NOT EXISTS idx_ep_tg_msg_id     ON email_processing(telegram_message_id);

-- Trigger pour updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_ep_updated_at
    BEFORE UPDATE ON email_processing
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================================================
-- Table : log d'audit
-- =============================================================================
CREATE TABLE IF NOT EXISTS audit_log (
    id                SERIAL PRIMARY KEY,
    gmail_message_id  VARCHAR(255),
    thread_id         VARCHAR(255),
    action            VARCHAR(100) NOT NULL,
    actor             VARCHAR(100) NOT NULL,  -- 'system' ou 'operator:12345'
    result            VARCHAR(20) DEFAULT 'success'
                        CHECK (result IN ('success', 'failure', 'skipped', 'demo')),
    details           JSONB,
    error_message     TEXT,
    is_demo           BOOLEAN DEFAULT FALSE,
    run_id            VARCHAR(50),
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_al_gmail_msg_id ON audit_log(gmail_message_id);
CREATE INDEX IF NOT EXISTS idx_al_action       ON audit_log(action);
CREATE INDEX IF NOT EXISTS idx_al_created_at   ON audit_log(created_at);
CREATE INDEX IF NOT EXISTS idx_al_actor        ON audit_log(actor);

-- =============================================================================
-- Table : statistiques par run
-- =============================================================================
CREATE TABLE IF NOT EXISTS run_stats (
    id                   SERIAL PRIMARY KEY,
    run_id               VARCHAR(50) UNIQUE NOT NULL,
    run_date             DATE NOT NULL,
    run_start            TIMESTAMP WITH TIME ZONE,
    run_end              TIMESTAMP WITH TIME ZONE,
    duration_seconds     INTEGER,

    -- Compteurs
    total_fetched        INTEGER DEFAULT 0,
    total_processed      INTEGER DEFAULT 0,
    total_duplicates     INTEGER DEFAULT 0,
    count_p1             INTEGER DEFAULT 0,
    count_p2             INTEGER DEFAULT 0,
    count_p3             INTEGER DEFAULT 0,
    count_high_risk      INTEGER DEFAULT 0,
    count_med_risk       INTEGER DEFAULT 0,
    count_low_risk       INTEGER DEFAULT 0,
    count_drafts_created INTEGER DEFAULT 0,
    count_sent           INTEGER DEFAULT 0,
    count_archived       INTEGER DEFAULT 0,
    count_errors         INTEGER DEFAULT 0,
    count_llm_fallback   INTEGER DEFAULT 0,

    -- Estimations
    estimated_time_saved_min INTEGER DEFAULT 0,

    is_demo              BOOLEAN DEFAULT FALSE,
    n8n_execution_id     VARCHAR(100),
    created_at           TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rs_run_date ON run_stats(run_date);

-- =============================================================================
-- Vue : résumé pour le digest Telegram
-- =============================================================================
CREATE OR REPLACE VIEW v_daily_digest AS
SELECT
    date_trunc('day', ep.created_at) AS day,
    COUNT(*)                          AS total,
    COUNT(*) FILTER (WHERE priority = 'P1') AS p1_count,
    COUNT(*) FILTER (WHERE priority = 'P2') AS p2_count,
    COUNT(*) FILTER (WHERE priority = 'P3') AS p3_count,
    COUNT(*) FILTER (WHERE risk_level = 'HIGH') AS high_risk_count,
    COUNT(*) FILTER (WHERE draft_id IS NOT NULL) AS drafts_count,
    COUNT(*) FILTER (WHERE state = 'SENT') AS sent_count,
    COUNT(*) FILTER (WHERE llm_fallback_used = TRUE) AS fallback_count,
    BOOL_OR(is_demo) AS any_demo
FROM email_processing ep
GROUP BY date_trunc('day', ep.created_at)
ORDER BY day DESC;

-- =============================================================================
-- Vue : emails en attente d'action opérateur
-- =============================================================================
CREATE OR REPLACE VIEW v_pending_actions AS
SELECT
    gmail_message_id,
    thread_id,
    from_email,
    from_name,
    subject,
    received_at,
    state,
    priority,
    category,
    risk_level,
    risk_score,
    needs_reply,
    recommended_action,
    draft_id,
    telegram_message_id,
    created_at
FROM email_processing
WHERE state IN ('AWAITING_APPROVAL', 'DRAFT_READY', 'RISK_REVIEW')
  AND operator_action IS NULL
ORDER BY
    CASE priority WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END,
    received_at DESC;

-- =============================================================================
-- Nettoyage TTL (à exécuter périodiquement)
-- =============================================================================
-- DELETE FROM email_processing WHERE created_at < NOW() - INTERVAL '30 days';
-- DELETE FROM audit_log WHERE created_at < NOW() - INTERVAL '30 days';
-- DELETE FROM run_stats WHERE run_date < NOW() - INTERVAL '60 days';

-- Message de confirmation
DO $$
BEGIN
    RAISE NOTICE 'POC Gmail Automation — Schéma DB initialisé avec succès';
END $$;

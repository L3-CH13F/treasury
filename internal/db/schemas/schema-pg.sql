BEGIN TRANSACTION;

-- Enable pgcrypto for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Tables

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL UNIQUE,
    password TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    organization_id UUID NOT NULL,
    idp_id UUID NOT NULL,
    FOREIGN KEY (idp_id) REFERENCES idps (id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id) REFERENCES organizations (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS secrets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    value BYTEA NOT NULL,  
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sso_id UUID NOT NULL,
    FOREIGN KEY (sso_id) REFERENCES idps (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sso_id UUID NOT NULL,
    FOREIGN KEY (sso_id) REFERENCES idps (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS group_users (
    group_id UUID NOT NULL,
    user_id UUID NOT NULL,
    FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    PRIMARY KEY (group_id, user_id)
);

CREATE TABLE IF NOT EXISTS permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    permission TEXT NOT NULL CHECK (permission IN ('read', 'edit', 'create', 'delete', 'permissions', 'owner')),
    require_mfa BOOLEAN NOT NULL DEFAULT FALSE,
    require_mpwd BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS rbac (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL,
    secret_id UUID NOT NULL,
    comment TEXT,
    FOREIGN KEY (secret_id) REFERENCES secrets (id) ON DELETE CASCADE,
    FOREIGN KEY (group_id) REFERENCES groups (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    secret TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    permission_id UUID NOT NULL,
    secret_id UUID NOT NULL,
    FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE,
    FOREIGN KEY (secret_id) REFERENCES secrets(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS idps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    logo_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    oidc_id UUID,
    FOREIGN KEY (oidc_id) REFERENCES oidc_providers (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS oidc_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id TEXT NOT NULL,
    client_secret TEXT NOT NULL,
    auth_url TEXT NOT NULL,
    user_info_url TEXT NOT NULL,
    jwks_url TEXT,
    scopes TEXT NOT NULL,
    user_identifier TEXT NOT NULL,
    redirect_uri TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  id INTEGER PRIMARY KEY NOT NULL,
  user INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  data TEXT,
  FOREIGN KEY (user) REFERENCES users (id) ON DELETE CASCADE
);

-- Indexes for Optimization

CREATE INDEX IF NOT EXISTS idx_group_users_user ON group_users (user_id, group_id);
CREATE INDEX IF NOT EXISTS idx_user_email ON users (email);
CREATE INDEX IF NOT EXISTS idx_created_at ON users (created_at);
CREATE INDEX IF NOT EXISTS idx_rbac_group ON rbac (group_id);
CREATE INDEX IF NOT EXISTS idx_api_keys ON api_keys (id, secret);

-- Triggers

CREATE OR REPLACE FUNCTION trg_create_user_group()
RETURNS TRIGGER AS $$
DECLARE 
    new_group_id UUID;
BEGIN
    INSERT INTO groups (id, name, description, created_at)
    VALUES (gen_random_uuid(), NEW.name || ' [Group]', NEW.name || ' [Group]', NOW())
    RETURNING id INTO new_group_id;
    
    INSERT INTO group_users (group_id, user_id)
    VALUES (new_group_id, NEW.id);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_insert
AFTER INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION trg_create_user_group();

CREATE OR REPLACE FUNCTION trg_update_user_group()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE groups
    SET name = NEW.name || ' [Group]'
    WHERE name = OLD.name || ' [Group]';
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_update
AFTER UPDATE OF name ON users
FOR EACH ROW
EXECUTE FUNCTION trg_update_user_group();

CREATE OR REPLACE FUNCTION trg_delete_user_group()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM groups WHERE name = OLD.name || ' [Group]';
    DELETE FROM group_users WHERE user_id = OLD.id;
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_delete
AFTER DELETE ON users
FOR EACH ROW
EXECUTE FUNCTION trg_delete_user_group();


-- Views    

CREATE VIEW IF NOT EXISTS user_vault AS 
SELECT 
    u.name AS user, 
    s.value AS password
FROM users u
JOIN group_users gu ON gu.user_id = u.id
JOIN rbac r ON r.group_id = gu.group_id
JOIN secrets s ON s.id = r.secret_id;

CREATE VIEW IF NOT EXISTS group_vault AS
SELECT 
    g.name AS group, 
    s.value AS password
FROM groups g
JOIN rbac r ON r.group_id = g.id
JOIN secrets s ON s.id = r.secret_id;

CREATE VIEW IF NOT EXISTS stale_passwords AS 
SELECT id FROM secrets 
WHERE id NOT IN (SELECT secret_id FROM rbac);

-- Data Insert

INSERT INTO idps (id, name, description)
SELECT gen_random_uuid(), 'treasury', 'treasury internal authentication engine'
WHERE NOT EXISTS (
    SELECT 1 FROM idps WHERE name = 'treasury'
);

COMMIT;

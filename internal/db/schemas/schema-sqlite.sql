BEGIN TRANSACTION;

-- Tables

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    email TEXT NOT NULL,
    password TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    organization INTEGER NOT NULL,
    idp INTEGER NOT NULL,
    FOREIGN KEY (idp) REFERENCES idps (id) ON DELETE CASCADE,
    FOREIGN KEY (organization) REFERENCES organizations (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS secrets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    value BLOB NOT NULL,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    sso INTEGER NOT NULL,
    FOREIGN KEY (sso) REFERENCES idps (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS organizations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    sso INTEGER NOT NULL,
    FOREIGN KEY (sso) REFERENCES idps (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS group_users (
    groups INTEGER NOT NULL,
    user INTEGER NOT NULL,
    FOREIGN KEY (groups) REFERENCES groups (id) ON DELETE CASCADE,
    FOREIGN KEY (user) REFERENCES users (id) ON DELETE CASCADE,
    PRIMARY KEY (groups, user)
);

CREATE TABLE IF NOT EXISTS permissions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT,
  created_at INTEGER NOT NULL,
  permission TEXT NOT NULL CHECK (permission IN ('read', 'edit', 'create', 'delete', 'permissions', 'owner')),
  require_mfa INTEGER NOT NULL DEFAULT 0,
  require_mpwd INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS rbac (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    groups INTEGER NOT NULL,
    password INTEGER NOT NULL,
    comment TEXT,
    FOREIGN KEY (password) REFERENCES secrets (id) ON DELETE CASCADE,
    FOREIGN KEY (groups) REFERENCES groups (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS api_keys (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    secret TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    permission INTEGER NOT NULL,
    password INTEGER NOT NULL,
    FOREIGN KEY (permission) REFERENCES permissions(id) ON DELETE CASCADE
    FOREIGN KEY (password) REFERENCES secrets(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS idps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT,
  logo_url TEXT,
  created_at INTEGER NOT NULL,
  oidc INTEGER,
  FOREIGN KEY (oidc) REFERENCES oidc_providers (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS oidc_providers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id TEXT NOT NULL,
  client_secret text NOT NULL,
  auth_url TEXT NOT NULL,
  user_info_url TEXT NOT NULL,
  jwks_url TEXT,
  scopes TEXT NOT NULL,
  user_identifier TEXT NOT NULL,
  redirect_uri TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_group_users_user ON group_users (user, groups);
CREATE INDEX IF NOT EXISTS idx_user_name ON users (name);
CREATE INDEX IF NOT EXISTS idx_user_id ON users (id);
CREATE INDEX IF NOT EXISTS idx_passwords_id ON secrets (id);
CREATE INDEX IF NOT EXISTS idx_rbac_group ON rbac (groups);
CREATE INDEX IF NOT EXISTS idx_api_keys ON api_keys (id, secret);

CREATE TRIGGER IF NOT EXISTS trg_user_insert 
  AFTER INSERT ON users
  FOR EACH ROW
  BEGIN
    INSERT INTO groups (name, description) VALUES (NEW.name, NEW.name | ' [Group]' );
    INSERT INTO group_users (groups, user) VALUES ((
      SELECT id
        FROM groups
      WHERE name = NEW.name | ' [Group]'
    ), NEW.id);
  END;

CREATE TRIGGER IF NOT EXISTS trg_user_update
  AFTER UPDATE OF name ON users
  FOR EACH ROW
  BEGIN
    UPDATE groups SET name = NEW.name | ' [Group]' WHERE groups.name = OLD.name | ' [Group]';
  END;

CREATE TRIGGER IF NOT EXISTS trg_user_delete
  AFTER DELETE ON users
  FOR EACH ROW
  BEGIN
    DELETE FROM groups WHERE groups.name = OLD.name | ' [Group]';
    DELETE FROM group_users WHERE user = OLD.id;
  END;


-- Views    

CREATE VIEW IF NOT EXISTS user_vault AS 
  SELECT user.name AS user, value AS password
    FROM users, secrets 
  INNER JOIN group_users 
    ON group_users.user = users.id
  INNER JOIN rbac
    ON rbac.groups = group_users.groups
  WHERE secrets.id = rbac.password;

CREATE VIEW IF NOT EXISTS group_vault AS
  SELECT groups.name AS groups, value AS password
    FROM groups, secrets 
  INNER JOIN rbac
    ON rbac.groups = groups.id
  WHERE secrets.id = rbac.password;

CREATE VIEW IF NOT EXISTS stale_passwords AS 
  SELECT id FROM (
    SELECT secrets.id AS id
      FROM secrets 
  EXCEPT
    SELECT secrets.id AS id
      FROM secrets 
    INNER JOIN rbac
      ON rbac.password = secrets.id
  );

-- Data

INSERT INTO idps (name, description)
  SELECT 'treasury', 'treasuries internal authentication engine'
  WHERE NOT(
    SELECT name FROM idps WHERE name = 'treasury'
  );

COMMIT;
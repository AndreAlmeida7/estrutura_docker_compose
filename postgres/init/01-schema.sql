-- Executado pelo entrypoint do Postgres apenas na primeira inicialização (volume vazio).
-- Mesmo schema criado por repository/postgres.py. Criar a tabela aqui evita a race
-- condition do "CREATE TABLE IF NOT EXISTS" quando várias réplicas do backend sobem
-- ao mesmo tempo contra um banco vazio (erro pg_type_typname_nsp_index).
CREATE TABLE IF NOT EXISTS game (
    game_id  TEXT PRIMARY KEY,
    password TEXT,
    attempts INTEGER
);

-- Jogo fixo usado pelo healthcheck do backend (docker/healthcheck.py) para validar
-- que a conexão com o banco está viva. Senha "healthcheck" em base64.
INSERT INTO game (game_id, password, attempts)
VALUES ('__healthcheck__', 'aGVhbHRoY2hlY2s=', 0)
ON CONFLICT (game_id) DO NOTHING;

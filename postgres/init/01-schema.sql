-- Roda só na criação do volume.
-- A tabela é a mesma que o backend cria. Criando antes, as 3 réplicas não disputam
-- o CREATE TABLE ao subir juntas (o que derrubava algumas delas).
CREATE TABLE IF NOT EXISTS game (
    game_id  TEXT PRIMARY KEY,
    password TEXT,
    attempts INTEGER
);

-- jogo usado pelo healthcheck do backend
INSERT INTO game VALUES ('__healthcheck__', 'aGVhbHRoY2hlY2s=', 0)
ON CONFLICT DO NOTHING;

-- Cria os bancos que o Evolution Go espera (POSTGRES_AUTH_DB / POSTGRES_USERS_DB).
-- A imagem postgres ja' cria 'evogo_auth' via POSTGRES_DB; aqui criamos o segundo.
-- Roda uma unica vez, no primeiro init do volume de dados do Postgres.
CREATE DATABASE evogo_users;

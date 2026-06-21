-- ====================================================================
-- Schema da automação de afiliados
-- Roda AUTOMATICAMENTE na primeira vez que o volume do Postgres é criado
-- (o n8n cria as tabelas dele sozinho; aqui criamos só as NOSSAS)
-- ====================================================================

-- Tabela principal: fila de ofertas
CREATE TABLE IF NOT EXISTS ofertas (
    id              SERIAL PRIMARY KEY,

    -- identidade do produto (pra deduplicacao)
    marketplace     VARCHAR(20)  NOT NULL DEFAULT 'shopee',
    produto_id      VARCHAR(120),              -- id do item na Shopee (itemid/shopid)
    url_produto     TEXT         NOT NULL,      -- url canonica do produto
    url_hash        VARCHAR(64)  NOT NULL,      -- hash da url p/ dedup rapida (UNIQUE abaixo)

    -- dados de exibicao
    titulo          VARCHAR(255) NOT NULL,
    preco           NUMERIC(10,2),
    preco_original  NUMERIC(10,2),
    desconto_pct    INT,                        -- calculado: % de desconto
    url_imagem      TEXT,
    categoria       VARCHAR(60),
    comissao_pct    NUMERIC(5,2),               -- % de comissao da Shopee p/ esse item

    -- o link que gera comissao (vem da API de afiliados Shopee)
    link_afiliado   TEXT,

    -- copy gerada pela IA (Gemini)
    copy_texto      TEXT,

    -- controle de fluxo
    status          VARCHAR(20)  NOT NULL DEFAULT 'pendente',
                    -- pendente | publicado | erro | descartado
    erro_msg        TEXT,                       -- guarda a falha se status=erro

    -- timestamps
    capturado_em    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    publicado_em    TIMESTAMPTZ
);

-- Dedup: nunca capturar a mesma url 2x
CREATE UNIQUE INDEX IF NOT EXISTS idx_ofertas_url_hash ON ofertas (url_hash);

-- Busca rapida do proximo item a publicar
CREATE INDEX IF NOT EXISTS idx_ofertas_status ON ofertas (status, capturado_em);

-- ====================================================================
-- Tabela de log de publicacoes (auditoria simples)
-- util pra saber o que foi postado e quando, sem depender do n8n
-- ====================================================================
CREATE TABLE IF NOT EXISTS publicacoes_log (
    id           SERIAL PRIMARY KEY,
    oferta_id    INT REFERENCES ofertas(id),
    canal        VARCHAR(30) NOT NULL,          -- telegram
    sucesso      BOOLEAN     NOT NULL,
    detalhe      TEXT,
    criado_em    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ====================================================================
-- View de conveniencia: o que esta na fila pronto pra publicar
-- (tem link de afiliado E copy gerada E ainda nao foi publicado)
-- ====================================================================
CREATE OR REPLACE VIEW v_fila_publicacao AS
SELECT id, titulo, preco, preco_original, desconto_pct,
       url_imagem, link_afiliado, copy_texto, capturado_em
FROM ofertas
WHERE status = 'pendente'
  AND link_afiliado IS NOT NULL
  AND copy_texto    IS NOT NULL
ORDER BY capturado_em ASC;

# History — Difrare

### 2026-07-20 — P1.2 dados reais (repo)
- Contexto: seed só com TODOs; agente `cliente` precisava de ICP/brand/ofertas reais.
- Decisão / entrega: PROFILE/brand/offers preenchidos a partir de difrare.com.br, brand Mart Art (`BRAND-OVERRIDE-DIFRARE.json`), Store API (preços/SKUs), MCP Mercado Pago (Woo + gateways), e-mails/contato (WhatsApp 15 98183-0000, Av. Amélio Schincariol 160 Tietê/SP). Meta/Google Ads IDs e tabela atacado ficaram `[A CONFIRMAR]`.
- Fonte: site oficial; repo `difrare/clidifrarev4`; MCP mercadopago-difrare / elementor; Store API.

### 2026-07-17 — Cupom BEMVINDA10
- Contexto: primeira compra `PRIMEIRA10` → `BEMVINDA10` (10%), anti-abuse CPF/CNPJ, acumulável com Pix.
- Fonte: plano cupom no repo Difrare / plugin mart-ecom.

### 2026-07-07 — Incidente LFI
- Contexto: IP 35.240.54.252 (GCloud Brussels) — milhares de requests LFI em difrare.com.br.
- Decisão: bloqueio `.htaccess` + fail2ban + report Google; container Easypanel `cliente-difrare`.
- Fonte: memória ops / incidente documentado.

### 2026-06-08 — Brand Mart Art aprovada
- Contexto: identidade “Italian Plum” + Playfair/Inter; princípio quarto branco / quadro italiano.
- Fonte: `BRAND-OVERRIDE-DIFRARE.json` (design partner Mart Art / Mart Studios).

# Story 2.2 — Barra secundária e espaçamento

Status: implemented
Epic: Epic 2 — Descoberta e densidade
Dependência: Story 1.1

## História

Como usuário, quero uma barra secundária próxima à menu bar e espaçamento ajustável,
para continuar acessando itens em Macs com notch ou pouco espaço horizontal.

## Critérios de aceitação

1. Modo automático usa barra secundária apenas quando houver overflow/notch; modo
   explícito respeita a escolha.
2. Barra preserva a ordem, não ativa o app, reancora ao monitor correto e fecha ao
   trocar Space/monitor conforme a política.
3. Presets compacto/padrão/espaçado e customizado limitado não alteram drag de
   terceiros nem a ordem persistida.
4. Auto-hide e fixação/desfixação não deixam janela órfã.

## Tarefas

- [x] Adicionar settings e defaults de spacing/presentation.
- [x] Aplicar spacing à barra secundária existente.
- [x] Validar monitor, notch, Space e teardown por código/roteiro.
- [x] Adicionar testes de layout e roteiro manual Developer.

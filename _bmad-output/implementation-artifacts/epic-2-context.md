# Epic 2 Context: Descoberta e densidade

## Goal

Tornar itens ocultos encontráveis e editáveis com segurança, preservando a ordem
real da menu bar e deixando claro quando a UI está apenas revelando itens para
edição. O resultado deve permitir localizar, revelar e ativar um item específico
sem transformar uma operação individual em uma alteração em lote.

## Stories

- **2.1 — Busca e ativação segura:** localizar itens por nome, ignorando caixa e
  acentos, mostrar a seção atual e ativar somente uma identidade revalidada.
- **2.2 — Barra secundária e espaçamento:** apresentar itens revelados próximos à
  menu bar, com ordem preservada, suporte a múltiplos monitores e espaçamento
  sanitizado.
- **2.3 — Identidade visível e movimentação unitária:** diferenciar status items
  com o mesmo rótulo e validar que apenas o item arrastado mudou de seção ou
  posição.
- **2.4 — Descoberta confiável e editor legível:** combinar a enumeração pública
  do WindowServer com a sonda privada, ocultar os divisores internos do Vorssaint
  e separar a identidade técnica do rótulo apresentado.
- **2.5 — Catálogo por Accessibility e correlação:** usar Accessibility como fonte
  de descoberta e WindowServer somente para identificar posição/movimento seguro.

## Requirements & Constraints

- O follow-up depende do contrato do Organizer MVP da PR #360: provider, snapshot,
  identidade, divisores e mover existentes continuam sendo reutilizados.
- As três seções permanecem `Visible`, `Hidden` e `Always Hidden`; revelar itens
  durante a edição não pode persistir uma classificação em lote.
- Rótulos duplicados devem receber fallback determinístico e compreensível, sem
  exibir PID, window ID ou outro dado privado.
- Uma tentativa com item protegido, identidade provisória, janela desaparecida,
  permissão ausente ou resultado pós-movimento ambíguo deve falhar de modo
  recuperável, sem mover itens adjacentes.
- A barra secundária não deve ativar a aplicação ao aparecer, deve desaparecer ou
  permanecer conforme a política existente e deve respeitar o monitor correto.
- Espaçamento é limitado e sanitizado; não se adicionam dependências externas,
  captura de tela ou conteúdo de menus.

## Technical Decisions

- Manter a separação entre regras puras de identidade/layout e efeitos AppKit,
  WindowServer, Accessibility e eventos globais.
- Usar a identidade completa do MVP no drag/drop e capturar snapshots antes e
  depois do comando de mover. A operação só confirma se o item selecionado é o
  único elemento alterado; caso contrário, descarta o undo e informa diagnóstico.
- Calcular rótulos únicos somente no contexto da lista exibida. O modelo persistido
  continua baseado em identidade estável, não em texto apresentado ao usuário.
- Preservar o comportamento seguro para versões futuras do macOS: se o provider
  não for compatível, o organizador permanece inerte.
- Cobrir sanitização, busca, rótulos duplicados e cardinalidade da alteração com
  testes determinísticos em `Tests/MetricsTests.swift`; validar TCC e apps reais
  manualmente com o bundle Developer.
- A lista privada de janelas é uma otimização, não uma fonte autoritativa: um
  item candidato da barra encontrado pela enumeração pública não pode sumir só
  porque uma versão do macOS retornou uma lista privada parcial.

## UX & Interaction Patterns

- A tela de organização deve comunicar que itens ocultos podem ser mostrados
  temporariamente para editar e que o drop afeta somente o item escolhido.
- Cada pill deve usar o nome acessível; quando houver colisão, mostrar um sufixo
  estável de ocorrência. O bloqueio de item protegido ou não identificado deve ser
  visível e impedir o gesto.
- Busca mostra seção e estado de identidade, revela a seção necessária e tenta
  ativar apenas após um refresh; falhas permanecem explicadas na própria UI.
- Barra secundária é ancorada ao monitor da menu bar, mantém a ordem do snapshot e
  não deve roubar foco nem interromper menus/interações em andamento.

## Cross-Story Dependencies

- Story 2.1 depende do modelo de sessão, preferências e gatilhos da Epic 1 e usa o
  mesmo provider/identidade para ativação.
- Story 2.2 depende dos divisores e da infraestrutura de janela do MVP, além da
  sanitização de espaçamento da Story 1.1.
- Story 2.3 depende da identidade e do mover da PR #360 e da apresentação da barra
  secundária da Story 2.2; sua validação protege as operações usadas por 2.1.
- Todas as stories compartilham o requisito de teardown idempotente, fallback sem
  Accessibility e testes no bundle Developer antes da entrega.

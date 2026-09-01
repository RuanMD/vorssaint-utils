---
status: in-review
baseline_commit: 39ca69606911a2801d7c4bf1b35b2dd1b49e89cf
---

# Story 2.3 — Identidade visível e movimentação unitária

Status: implemented-pending-manual-validation
Epic: Epic 2 — Descoberta e densidade
Dependências: Stories 1.1 e 2.2
Branch: feat/menu-bar-manager-followup

## Problema observado

Ao tentar mover um item de `Sempre ocultos` para `Visíveis`, a tela revela vários
itens ao mesmo tempo e a experiência parece mover o grupo inteiro. Além disso,
vários status items do mesmo aplicativo aparecem com o mesmo nome, embora tenham
identidades e `windowID`s diferentes.

## História

Como usuário, quero distinguir cada status item e mover somente o item que
selecionei, para organizar a barra sem ambiguidade nem movimentação em lote.

## Critérios de aceitação

1. Given dois ou mais itens do mesmo app, When eles aparecem no editor, Then cada
   item tem um rótulo distinguível; quando não houver título acessível, usar um
   sufixo determinístico baseado na ocorrência/identidade.
2. Given um item selecionado para drag-and-drop, When o movimento é concluído,
   Then somente o `windowID`/`MenuBarItemIdentity` selecionado muda de seção ou
   posição.
3. Given que a sessão revela temporariamente itens ocultos para editar, When a
   revelação acontece, Then a UI comunica que é uma visualização transitória e
   não grava classificação em lote.
4. Given que a verificação pós-movimento encontra mais de um item alterado,
   When a operação termina, Then ela é tratada como falha recuperável, o estado
   persistido não é confirmado e o usuário recebe diagnóstico.
5. Given item protegido ou identidade provisória, When o usuário tenta arrastar,
   Then o item continua bloqueado e nenhum outro item é movido.
6. Given itens com o mesmo nome visível, When o teste determinístico é executado,
   Then identidade, rótulo e destino permanecem estáveis após refresh/restart.

## Tarefas

- [x] Separar visualmente `reveal for editing` de `move one item`.
- [x] Exibir fallback único para nomes repetidos sem expor PID ou dados privados.
- [x] Capturar o conjunto de window IDs antes/depois e validar cardinalidade 1.
- [x] Garantir que drop delegate e `MenuBarItemMover` usem a identidade completa.
- [x] Adicionar testes de identidade duplicada, movimento unitário e rollback.
- [ ] Validar manualmente com vários status items do Vorssaint, Google Drive e
  aplicativos hospedados pelo Control Center.

## Notas de implementação

- O editor e a barra secundária agora calculam rótulos únicos no contexto do
  snapshot, usando `#N` determinístico para colisões e sem mostrar IDs técnicos.
- O serviço captura a lista ordenada antes do Command-drag e só confirma o
  movimento quando a identidade selecionada é a única removida/reinserida entre
  as seções. O reflow dos vizinhos é aceito; movimentação em lote é rejeitada e
  o undo não é confirmado.
- Um aviso na tela explica que revelar as seções durante a edição é transitório.
- A validação manual continua necessária com Accessibility concedida no bundle
  `com.vorssaint.utils.dev`, incluindo apps reais, notch e Control Center.

## Arquivos prováveis

`Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarOrganizerSupport.swift`,
`MenuBarOrganizerService.swift`, `MenuBarItemMover.swift`,
`UI/Settings/MenuBarOrganizerSettings.swift`, `MenuBarOrganizerPanels.swift` e
`Tests/MetricsTests.swift`.

## Handoff

Encaminhar para `bmad-agent-dev`/`vorssaint-implementer` na mesma branch
`feat/menu-bar-manager-followup`. Não criar uma branch paralela nem reimplementar
o provider da PR #360.

- `resource_slug`: `menu-bar-manager-followup`
- `worktree`: `/Users/ruansantana/Documents/DeepAgent/vorssaint-utils-menu-bar-manager`
- `base`: `upstream/main` (`b0dde6567f2945f474cdd91b9478ba3ed44aa0a5`), com dependência
  local no head da PR #360 (`18383b9`)
- objetivo: corrigir somente identidade visível e movimentação unitária do
  Organizer MVP; a implementação não é independente da PR #360

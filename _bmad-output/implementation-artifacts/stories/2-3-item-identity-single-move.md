# Story 2.3 — Identidade visível e movimentação unitária

Status: ready-for-dev
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

- [ ] Separar visualmente `reveal for editing` de `move one item`.
- [ ] Exibir fallback único para nomes repetidos sem expor PID ou dados privados.
- [ ] Capturar o conjunto de window IDs antes/depois e validar cardinalidade 1.
- [ ] Garantir que drop delegate e `MenuBarItemMover` usem a identidade completa.
- [ ] Adicionar testes de identidade duplicada, movimento unitário e rollback.
- [ ] Validar manualmente com vários status items do Vorssaint, Google Drive e
  aplicativos hospedados pelo Control Center.

## Arquivos prováveis

`Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarOrganizerSupport.swift`,
`MenuBarOrganizerService.swift`, `MenuBarItemMover.swift`,
`UI/Settings/MenuBarOrganizerSettings.swift`, `MenuBarOrganizerPanels.swift` e
`Tests/MetricsTests.swift`.

## Handoff

Encaminhar para `bmad-agent-dev`/`vorssaint-implementer` na mesma branch
`feat/menu-bar-manager-followup`. Não criar uma branch paralela nem reimplementar
o provider da PR #360.

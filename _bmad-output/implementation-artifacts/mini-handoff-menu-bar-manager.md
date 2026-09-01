# Mini handoff — Menu Bar Manager

## Onde continuar

- Branch: `feat/menu-bar-manager-followup`
- Worktree: `/Users/ruansantana/Documents/DeepAgent/vorssaint-utils-menu-bar-manager`
- HEAD: `e3f4d36` — `fix(menu-bar): resolve icons and eliminate duplicate items`
- Dependência: PR #360 / head local `18383b9`
- Bundle de teste instalado: `/Applications/Vorssaint (Developer).app`
  (`com.vorssaint.utils.dev`, build `6cbec5e`)

## O que foi corrigido

O macOS 26 pode compor toda a status bar em uma única janela; portanto, o
Organizer não pode depender apenas de `CGWindowList` para descobrir ícones.

- `MenuBarItemSourceResolver` cria um catálogo cacheado via `AXExtrasMenuBar`.
- `MenuBarWindowProvider` usa Accessibility para descoberta e WindowServer apenas
  para correlacionar posição/movimento.
- Candidatos AX sem janela correlacionada devem aparecer no editor com nome/ícone,
  mas ficam bloqueados (`isMovable == false`).
- Divisores internos `Vorssaint.MenuBarOrganizer.*` são excluídos.
- A barra secundária inclui somente itens movíveis/correlacionados.
- Evitada varredura AX duplicada no refresh.
- **`6cbec5e`**: Itens das lanes do editor exibem apenas ícone (sem texto/rótulo
  "#N"); nome completo disponível no tooltip de hover. Indicadores de bloqueio e
  identidade provisória mantidos como badge pequeno.
- **`6cbec5e`**: Setas das divisórias na status bar colapsam seções corretamente
  mesmo com o painel de Ajustes aberto (removida a guarda `editingCount == 0`
  em `applyDividerState`). A classificação de seção via `midX` dos divisores se
  mantém correta após o colapso porque a ordenação relativa item/divisor é
  preservada.
- Scroll indicator das lanes ocultado (ruído visual).

## Próxima validação manual

1. Abrir **Vorssaint (Developer) → Barra de menus → Atualizar** com Accessibility
   concedida ao bundle Developer.
2. Comparar o editor com a status bar real: Google Drive/QSpace/Orca/VoiceInk/
   TickTick e demais apps que expõem `AXExtrasMenuBar` devem aparecer uma vez.
3. Confirmar que itens só-AX têm nome/ícone e lock, não `?` nem ID técnico.
4. Confirmar que nenhum item `Vorssaint.MenuBarOrganizer.*` aparece na lista.
5. Arrastar somente um item confirmado entre seções; itens bloqueados não podem
   iniciar drag e a barra secundária não deve listar itens não correlacionados.
6. Se ainda faltar ícone, registrar: app, ícone visível na barra, se aparece no
   editor, se tem lock, seção e captura. Não registrar dados sensíveis.

## Arquivos relevantes

- `Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarItemSourceResolver.swift`
- `Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarWindowProvider.swift`
- `Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarOrganizerSupport.swift`
- `Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarOrganizerPanels.swift`
- `Tests/MetricsTests.swift`
- Story: `stories/2-5-accessibility-catalog-correlation.md`

## Validação já feita

`./build.sh --test` passou com **9.477 checks**; `--selftest`, assinatura e
instalação Developer passaram no commit `a9e5ae6`.

## Regras

- Não criar outra branch/worktree; continuar neste follow-up.
- Não copiar código/dependências do Thaw. Ele foi baixado somente em `/tmp` para
  referência arquitetural.
- Não liberar movimento sem correlação de janela verificável.
- Sem `push`, PR ou substituição do app oficial sem autorização do usuário.

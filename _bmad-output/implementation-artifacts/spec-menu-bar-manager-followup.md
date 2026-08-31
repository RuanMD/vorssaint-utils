# Especificação — Menu Bar Manager: interação e descoberta

## Tipo e dependência

- PR de follow-up, não independente.
- Branch exclusiva: `feat/menu-bar-manager-followup`.
- Worktree obrigatório para implementação: `/Users/ruansantana/Documents/DeepAgent/vorssaint-utils-menu-bar-manager`.
- Não implementar este recurso em `main`, em outra branch de feature ou no checkout
  compartilhado com outra IA.
- Depende da integração da PR #360, que fornece `MenuBarOrganizerService`,
  `ManagedMenuBarItem`, `MenuBarWindowProvider`, divisores e barra secundária.
- Base efetiva da branch: `upstream/main` em `b0dde656`, com o head da dependência
  PR #360 (`18383b9`) mesclado localmente como follow-up dependente. A #360 ainda
  está aberta; não tratar esta branch como PR independente.

Antes de começar, confirmar `git branch --show-current`, `git status --short`, a
base real e a existência da dependência. Registrar qualquer mudança de base neste
arquivo e no handoff antes de alterar código.

## Code Map

### Núcleo puro

- `Sources/Vorssaint/Core/MenuBarOrganizerAdvancedSupport.swift`
  - `MenuBarRevealTrigger` e normalização dos gatilhos;
  - `MenuBarRehidePolicy` e cálculo de deadline/pausa;
  - `MenuBarSpacingPreset` e limites do valor customizado;
  - busca normalizada por acentos, estado e relevância;
  - decisões sem AppKit para teste determinístico.
- `Sources/Vorssaint/Core/Defaults.swift`
  - novas chaves e valores registrados, mantendo as chaves do MVP sem renomear.
- `Sources/Vorssaint/Core/GlobalShortcut.swift`
  - roles do organizador, defaults, conflitos e gating por disponibilidade.
- `Sources/Vorssaint/Core/SettingsBackupSupport.swift`
  - inclusão das preferências portáveis; exclusão de estado de máquina.

### Integração de serviço

- `Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarOrganizerService.swift`
  - registrar/remover gatilhos de forma idempotente;
  - coordenar reveal, search activation, timer e teardown;
  - nunca iniciar provider em macOS 27+ ou sem Accessibility;
  - cancelar timers/tasks e liberar monitores ao desligar.
- `Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarOrganizerHotkeyService.swift`
  - registrar os cinco roles Carbon somente quando habilitados e sem conflito.
- `Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarOrganizerSearchPanel.swift`
  - painel de busca não ativador e seleção de item.
- `Sources/Vorssaint/Services/MenuBarOrganizer/MenuBarOrganizerPanels.swift`
  - search panel e aplicar spacing à barra secundária existente;
  - manter janela não ativadora, multi-monitor e fechamento por mudança de Space.

### Superfícies

- `Sources/Vorssaint/UI/Settings/MenuBarOrganizerSettings.swift`
  - controles de gatilho, auto-rehide, spacing e diagnóstico.
- `Sources/Vorssaint/UI/Settings/ShortcutsSettings.swift`
  - rows dos roles do organizador usando `ShortcutRecorderButton`.
- `Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift`
  - ação “buscar itens da menu bar” e ações de reveal/hide, condicionadas à
    disponibilidade real do organizer.
- `Sources/Vorssaint/UI/Settings/SettingsDirectory.swift` e
  `Sources/Vorssaint/UI/Settings/SettingsView.swift`
  - rota e palavras-chave da página após a dependência existir.
- `Sources/Vorssaint/Core/MenuBarOrganizerAdvancedStrings.swift`
  - textos das superfícies avançadas; fallback em inglês para idiomas ainda não
    especializados.
- `docs/PERMISSIONS.md`
  - explicar Accessibility contextual e confirmar ausência de Screen Recording.

### Testes e build

- `Tests/MetricsTests.swift`
  - sanitização, ranking, deadlines, pausa durante menu, gating, conflitos,
    migração e export/import do backup.
- `build.sh`
  - incluir somente novos arquivos Swift quando a lista de fontes for explícita.

## Tarefas ordenadas

1. Confirmar que #360 foi integrado e capturar o hash-base; sem isso, não iniciar
   implementação de integração.
2. Implementar modelos e sanitizadores puros; adicionar testes antes dos monitores.
3. Adicionar defaults, backup e roles de atalho com valores desabilitados/seguros.
4. Adaptar `MenuBarOrganizerService` com sessão cancelável, refresh pós-reveal e
   auto-rehide que respeita menus/interação.
5. Adicionar search panel com identidade e verificação de window/item.
6. Integrar Command Bar e Settings, incluindo localização.
7. Integrar spacing somente à barra secundária/divisores, sem interferir no drag.
8. Rodar testes focados e comandos obrigatórios; instalar apenas o bundle Developer
   se não houver outro worktree usando-o.
9. Fazer revisão de diff/segredos/teardown e preparar commit/PR sem push autorizado.

## Casos-limite obrigatórios

| Caso | Resultado esperado |
|---|---|
| Accessibility ausente/revogada | orientação explícita, serviço parado, demais features intactas |
| macOS 27+ | feature não instala/inicializa; configuração preservada e inerte |
| item provisório | pode ser exibido na lista, não pode receber clique/movimento automático |
| item desaparece entre busca e ativação | falha recuperável após snapshot novo |
| menu aberto durante deadline | deadline pausado/adiado; nenhum menu é fechado pelo organizer |
| app/organizer concorrente detectado | não iniciar ou parar de forma idempotente; mostrar conflito |
| atalho duplicado/registro falha | rejeitar ou marcar falha, sem sequestrar atalho de outra feature |
| custom spacing inválido | sanitizar para intervalo e persistir apenas valor válido |
| monitor/Space muda | fechar/reancorar barra secundária e atualizar snapshot |
| backup antigo/sem chaves novas | usar defaults; não apagar preferências existentes não relacionadas |

## Verificação

```sh
./build.sh --test
./build/Vorssaint --selftest
./build.sh --dev
./build.sh
git diff --check
git grep --cached -n -E 'AKIA|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|xox[baprs]-'
```

Validação manual obrigatória da variante Developer:

```sh
./build.sh --dev --install
open "/Applications/Vorssaint (Developer).app"
```

Roteiro: negar/conceder Accessibility no bundle Developer; testar três seções,
hover, clique vazio, atalhos, busca, auto-rehide com menu aberto, notch, monitor
externo, auto-hide da menu bar, troca de Space, app concorrente e organizer
desligado. Não declarar testados hardware, múltiplos monitores reais ou TCC sem
executar o roteiro.

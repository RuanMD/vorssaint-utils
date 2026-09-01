# Handoff para implementação por outra IA — Menu Bar Manager avançado

## 1. Contrato operacional obrigatório

Este documento entrega uma implementação para a branch do recurso. Antes de
qualquer edição, a IA implementadora deve executar:

```sh
git branch --show-current
git status --short --branch
git remote -v
git log -1 --oneline
```

Valores esperados neste handoff:

| Campo | Valor |
|---|---|
| `resource_slug` | `menu-bar-manager-followup` |
| branch | `feat/menu-bar-manager-followup` |
| worktree | `/Users/ruansantana/Documents/DeepAgent/vorssaint-utils-menu-bar-manager` |
| base atual | `upstream/main` em `b0dde6567f2945f474cdd91b9478ba3ed44aa0a5` |
| tipo | follow-up dependente, não PR independente |
| dependência | PR #360 — Menu Bar Organizer MVP |
| objetivo | interação e descoberta dos itens já organizados |

Se a branch, o worktree ou a base não corresponderem, parar antes de editar e
informar a divergência. Não usar `stash`, `reset`, `checkout`, merge destrutivo ou
descarte de alterações para liberar um checkout ocupado. Não implementar em
`main`, em outra branch de feature ou em um worktree compartilhado.

## 2. Estado do trabalho

O PRD e a especificação já foram produzidos em:

- `_bmad-output/planning-artifacts/prds/prd-menu-bar-manager-advanced/prd.md`
- `_bmad-output/implementation-artifacts/spec-menu-bar-manager-followup.md`

A PR #360 é a dependência canônica do núcleo do organizer e continua aberta neste
handoff. A branch já incorpora seu head (`18383b9`) sobre `upstream/main`
(`b0dde656`). Não criar uma implementação paralela das três seções, enumeração ou
movimentação; o código novo apenas expande o serviço existente.

O Ice foi consultado somente para entender comportamentos de produto e separar
responsabilidades. Não copiar código, nomes de tipos, assets, textos, arquitetura,
`AXSwift` ou qualquer outra dependência do Ice. Reimplementar a solução usando as
abstrações nativas e os padrões já existentes no Vorssaint.

## 3. Escopo do MVP deste follow-up

Implementar sobre o contrato da #360:

1. revelar Hidden e Always Hidden com estados independentes;
2. gatilhos configuráveis: botão do Vorssaint, atalho global, hover e clique em
   área vazia; tratar scroll/swipe somente se os monitores existentes permitirem
   isso sem nova permissão;
3. auto-rehide por clique fora, 3 s, 5 s, 10 s, 30 s ou duração customizada;
4. pausar/adiar o rehide enquanto menu, submenu, clique ou interação do item
   revelado estiverem ativos;
5. Menu Bar Search por atalho e pela Command Bar, com ativação best-effort depois
   de revelar e revalidar o item;
6. espaçamento compacto, padrão, espaçado e customizado sanitizado;
7. persistência, backup/restauração das preferências e diagnóstico de falhas;
8. continuidade segura quando Accessibility for negada/revogada, quando outro
   organizer estiver ativo ou quando o macOS for 27+.

Não implementar neste recurso:

- aparência/tint/gradiente/transparência/sombra da menu bar;
- perfis nomeados;
- grupos expansíveis;
- automações por app, VPN, bateria, microfone, monitor ou Focus Mode;
- backend macOS 27 baseado em `MenuBarAgent`;
- ocultação dos menus do aplicativo à esquerda;
- nova dependência externa ou cópia de implementação de terceiros.

## 4. Arquitetura a preservar

Manter a separação do Vorssaint:

- regras de normalização, busca, deadlines e sanitização em `Core`, puras e
  testáveis;
- coordenação, monitores, janelas e Accessibility em `Services`, sem importar
  SwiftUI;
- configurações, atalhos, busca e diagnóstico em `UI`/Command Bar;
- `FeatureRuntime` como dono do binding e do teardown;
- `DefaultsKey`/`@AppStorage` para preferências não secretas;
- `SettingsBackupSupport` somente com preferências portáveis, nunca window IDs,
  PID, snapshots, imagens ou estado momentâneo;
- callbacks e Tasks identificados por sessão e canceláveis;
- `PermissionRow` e `Permissions.shared`, sem falha silenciosa;
- localização para todos os textos novos.

O mapa original está na `spec-menu-bar-manager-followup.md`; os arquivos efetivos
já implementados são `MenuBarOrganizerAdvancedSupport.swift`,
`MenuBarOrganizerAdvancedStrings.swift`, `MenuBarOrganizerHotkeyService.swift` e
`MenuBarOrganizerSearchPanel.swift`, além da extensão do service/settings/panels.
O monitor de eventos ficou no próprio service para preservar o ciclo de vida
idempotente; não criar um segundo monitor paralelo.

## 5. Modelo comportamental mínimo

Manter uma sessão explícita do organizer:

```text
disabled -> enabled/idle -> revealed(hidden/all) -> rehiding -> enabled/idle
                    \\-> unavailable (permission, macOS, conflict)
```

Regras invariantes:

- Hidden e Always Hidden não compartilham um toggle que torne impossível saber o
  estado de cada seção;
- revelar não altera ordem nem classificação persistida;
- cada rehide usa um snapshot/configuração capturado no início da operação;
- timer vencido não fecha menu aberto nem envia clique fora do alvo;
- ação de busca revela, aguarda refresh, verifica identidade e só então tenta
  ativar; item provisório ou desaparecido resulta em erro recuperável;
- monitor global devolve eventos que não pertencem à área/estado do organizer;
- desligar, revogar permissão, trocar Space/monitor e perder a condição do provider
  desmontam de forma idempotente;
- macOS 27+ mantém preferências e explica indisponibilidade sem inicializar o
  provider incompatível.

## 6. Sequência de implementação

Executar na ordem abaixo, mantendo cada etapa compilável:

1. Confirmar #360, provider real, APIs e hash-base. Atualizar este handoff se a
   dependência mudar.
2. Escrever testes de regras puras para triggers, política de rehide, pausa,
   ranking de busca, identidade, spacing, conflitos, migração e backup.
3. Implementar modelos e sanitizadores em `Core`, com defaults seguros e feature
   desligada por padrão quando a compatibilidade não puder ser garantida.
4. Adicionar roles de atalhos sem sequestrar combinações existentes e sem fazer o
   funcionamento depender do registro global.
5. Integrar sessão, monitores, refresh pós-reveal, auto-rehide e teardown no
   serviço existente da #360.
6. Integrar busca: listar snapshot, revelar seção correta, esperar snapshot novo,
   revalidar identidade e ativar apenas quando seguro.
7. Integrar barra secundária existente, monitor/Space, auto-hide e spacing sem
   interferir em drag ou em itens de terceiros.
8. Integrar Settings, Command Bar, localização, backup e diagnóstico de permissão.
9. Rodar verificação completa e revisar o diff contra a base declarada.

## 7. TCC e validação manual

Accessibility é específica por bundle. Validar a variante Developer (`com.vorssaint.utils.dev`):

1. build limpa sem Accessibility;
2. abrir Organizer e verificar orientação explícita/`PermissionRow`;
3. confirmar que as demais features continuam funcionando;
4. conceder Accessibility, retornar ao app e fazer refresh;
5. testar três seções, atalhos, hover/clique, busca e auto-rehide;
6. revogar durante a sessão e verificar teardown sem crash;
7. testar notch, barra secundária, monitor externo, troca de Space, auto-hide da
   menu bar e outro organizer em execução;
8. confirmar que Screen Recording nunca é solicitado.

O serviço não pode iniciar provider nem monitor global quando a permissão estiver
ausente. O botão local e a UI devem continuar explicando o estado. Não declarar
hardware, múltiplos monitores ou TCC como testados sem executar o roteiro.

## 8. Verificação e entrega

Rodar, quando houver código:

```sh
swift build
./build.sh --test
./build/Vorssaint --selftest
./build.sh --dev
./build.sh
./build.sh --dev --install
git diff --check
git diff --stat upstream/main...HEAD
git log --oneline upstream/main..HEAD
```

Resultado automatizado atual: `swift build` e `./build.sh --test` passam; o harness
reporta 9.470 checks. A validação Developer em hardware real ainda é necessária
para TCC, notch, múltiplos monitores, Spaces e interação com organizer concorrente.
Foi identificada uma correção de curso na Story 2.3: rótulos repetidos e a
revelação transitória durante edição fazem uma movimentação unitária parecer em
lote. Implementar a validação de cardinalidade por `windowID` e o fallback de
rótulo antes de considerar o Organizer pronto para uso manual.
Não fazer `git push`, force-push ou abrir PR sem autorização explícita. Antes da
entrega, informar branch, commit, base/dependência, arquivos principais, testes,
build Developer, limitações manuais, permissões e qualquer trabalho adiado.

Definição de pronto: os critérios de aceitação do PRD estão cobertos por testes ou
roteiro manual, a branch contém somente este follow-up e seus artefatos necessários,
nenhum recurso do MVP foi duplicado, nenhum segredo foi introduzido e o comportamento
de permissão/indisponibilidade é explicável e recuperável.

---
title: 'Proteção para ⌘Q e ⌘W'
type: 'feature'
created: '2026-08-31'
status: 'ready-for-development'
context:
  - '_bmad-output/planning-artifacts/project-context.md'
---

<frozen-after-approval reason="escopo fornecido pelo usuário no mini PRD">

## Intent

**Problema:** ⌘Q encerra o aplicativo e ⌘W fecha a janela imediatamente; um toque acidental pode interromper trabalho, gravações ou processos.

**Abordagem:** adicionar uma feature opcional que intercepta somente ⌘Q e ⌘W, com configuração independente por atalho, confirmação local e cancelável. A ação original continua sendo executada pelo macOS somente depois de uma confirmação válida.

## Boundaries & Constraints

**Always:** manter ⌘C, ⌘V, ⌘T, cliques com Command e demais atalhos sem Command-Q/Command-W intactos; respeitar o caractere resolvido pelo layout do teclado; manter o HUD não-ativante; encerrar event tap, timers e HUD ao desligar.

**Ask First:** nenhuma decisão adicional necessária para o incremento descrito.

**Never:** interceptar Command globalmente, bloquear teclas não relacionadas, persistir conteúdo de janelas, usar rede, adicionar dependências ou enviar push/abrir PR sem autorização explícita.

## Requirements

- **FR-1:** cada atalho (⌘Q e ⌘W) pode ser ligado/desligado separadamente.
- **FR-2:** cada atalho oferece `hold`, `doublePress` e `extraModifier`.
- **FR-3:** hold usa duração configurável; soltar antes cancela.
- **FR-4:** double press usa intervalo consecutivo configurável; a primeira pressão aguarda e a segunda confirma.
- **FR-5:** extra modifier exige Shift, Option ou Control além de Command; o Command puro não fecha.
- **FR-6:** cada atalho oferece `all`, `selectedOnly` e `allExceptSelected`, com exceções por bundle identifier.
- **FR-7:** o feedback visual pode ser desligado e nunca rouba foco.
- **FR-8:** Escape cancela uma confirmação pendente.
- **FR-9:** a proteção usa o caractere do evento e só usa o key code QWERTY como fallback para layouts que não expõem caractere.

## Given / When / Then

| ID | Given | When | Then |
|---|---|---|---|
| QWP-1 | ⌘Q está desligado | o usuário pressiona ⌘Q | o evento chega ao app sem atraso ou HUD |
| QWP-2 | ⌘Q está em hold com 800 ms | o usuário solta antes de 800 ms | ⌘Q não chega ao app e a confirmação é cancelada |
| QWP-3 | ⌘Q está em hold com 800 ms | o usuário mantém por 800 ms e solta | a ação original de ⌘Q é executada uma vez |
| QWP-4 | ⌘W está em double press | o usuário pressiona uma vez | ⌘W não fecha a janela e o HUD pede nova pressão |
| QWP-5 | ⌘W está em double press | a segunda pressão ocorre dentro do intervalo | a ação original de ⌘W é executada uma vez |
| QWP-6 | ⌘Q exige Shift | o usuário pressiona ⌘Q puro | ⌘Q não fecha e o HUD orienta usar Shift+⌘Q |
| QWP-7 | ⌘Q exige Shift | o usuário pressiona Shift+⌘Q | o evento original é liberado uma vez e a ação é executada |
| QWP-8 | um app está fora do escopo configurado | o usuário usa o atalho protegido | o evento passa sem confirmação |
| QWP-9 | há confirmação pendente | o usuário pressiona Escape | a confirmação é cancelada e o app não recebe Q/W |
| QWP-10 | a feature está ativa | o usuário pressiona ⌘C, ⌘V, ⌘T ou Command+clique | o evento não é consumido pela feature |

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior |
|---|---|---|
| HOLD_CANCEL | key down seguido de key up antes do limite | limpar timer e estado; nenhum key down sintético |
| DOUBLE_TIMEOUT | primeira pressão sem segunda no intervalo | limpar estado; não executar a ação |
| DOUBLE_OTHER_KEY | primeira pressão seguida de outra tecla | cancelar a confirmação e liberar a outra tecla |
| MODIFIER_RELEASE | hold pendente perde Command/extra modifier | cancelar sem executar |
| ESCAPE | confirmação pendente + Escape | consumir Escape, esconder HUD e cancelar |
| LAYOUT | evento com caractere q/w e key code não-QWERTY | reconhecer pelo caractere; não confundir tecla física |
| TAP_DISABLED | macOS desabilita o event tap por timeout | rearmar o tap, cancelar estado pendente e deixar eventos passarem |
| TEARDOWN | feature desligada, indisponível ou Accessibility revogada | remover tap, timer, observer e HUD de forma idempotente |

## Code Map

- `Sources/Vorssaint/Core/QuitProtectionSupport.swift` — enums de configuração, sanitização, escopo e matching puro.
- `Sources/Vorssaint/Core/QuitProtectionStrings.swift` — nome, descrição, configurações e HUD localizados.
- `Sources/Vorssaint/Core/Defaults.swift` — chaves e defaults não secretos para ⌘Q/⌘W.
- `Sources/Vorssaint/Services/QuitProtection/QuitProtectionService.swift` — event tap, máquina de estados, timers, app ativo, teardown e repostagem única.
- `Sources/Vorssaint/UI/QuitProtection/QuitProtectionHUD.swift` — NSPanel `.nonactivatingPanel` para feedback discreto.
- `Sources/Vorssaint/UI/Settings/QuitProtectionSettings.swift` — controles independentes, exceções e Accessibility.
- `Sources/Vorssaint/Core/FeatureCatalog.swift`, `Sources/Vorssaint/App/FeatureRuntime.swift` — identidade, permissão, binding e ciclo de vida.
- `Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift`, `SettingsView.swift`, `SettingsDirectory.swift`, `FeatureHubSettings.swift` — navegação e descoberta.
- `Sources/Vorssaint/Core/SettingsBackupSupport.swift` — exportação das preferências não secretas.
- `Tests/MetricsTests.swift` e `build.sh` — regras puras, contratos e compilação da suíte.

## Persistência, permissões e riscos

- Preferências: UserDefaults, sem credenciais nem conteúdo de aplicativos.
- Permissão: Accessibility, necessária para o CGEvent tap global; nenhuma nova permissão.
- Dados locais: nenhum arquivo, histórico ou rede.
- Riscos: conflito com outros event taps, revogação de TCC, apps que tratam Q/W de forma incomum e validação manual de múltiplos layouts.
- Compatibilidade: macOS 14+, APIs AppKit/CoreGraphics nativas, sem dependências novas.

## Tasks & Verification

- [ ] Adicionar catálogo, defaults, backup, runtime e localização.
- [ ] Implementar matching e máquina de confirmação testáveis.
- [ ] Implementar event tap, repostagem única e HUD não-ativante.
- [ ] Adicionar Settings e seleção de apps por atalho.
- [ ] Adicionar testes de defaults, escopo, layouts, hold/double/extra modifier e teardown estrutural.
- [ ] Executar `./build.sh --test`, `./build/Vorssaint --selftest`, `./build.sh --dev` e `./build.sh`.
- [ ] Fazer validação manual com Accessibility, apps reais, múltiplos layouts e atalhos não relacionados.

</frozen-after-approval>

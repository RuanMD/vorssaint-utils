# PRD — Menu Bar Manager avançado

Status: implementado na branch de follow-up; pendente de validação manual
Idioma: português
Base: `upstream/main` em 31/08/2026

## Contrato de branch para implementação por IA

- `resource_slug`: `menu-bar-manager-followup`
- branch alvo: `feat/menu-bar-manager-followup`
- worktree: `/Users/ruansantana/Documents/DeepAgent/vorssaint-utils-menu-bar-manager`
- base atual: `upstream/main` (`b0dde6567f2945f474cdd91b9478ba3ed44aa0a5`)
- dependência: PR #360, ainda aberta; head usado localmente: `18383b9`
- tipo: follow-up, não independente
- objetivo único: interação e descoberta sobre o Menu Bar Organizer, sem incluir
  aparência, perfis, grupos, automações ou backend macOS 27

A outra IA deve confirmar esses dados antes de editar. Se a PR #360 ainda não
estiver integrada, não implementar contra uma cópia concorrente do MVP; manter a
branch como dependente e registrar o novo commit-base no handoff.

## Decisão de produto

O Vorssaint deve evoluir o Menu Bar Organizer para um gerenciador de prioridades
da menu bar: a pessoa decide o que fica visível, o que aparece sob demanda e como
encontra itens escondidos quando precisa deles.

Esta não é uma implementação concorrente do MVP. A PR #360
([Add hardened menu bar organizer MVP](https://github.com/vorssaintapp/vorssaint-utils/pull/360))
é a dependência canônica: ela fornece as três seções, os divisores nativos, a
enumeração/movimentação segura, a barra secundária e a tela de organização. O
follow-up acrescenta a camada de interação e descoberta em cima desse contrato.

O Ice foi usado somente como referência de comportamento e decomposição. O código,
os nomes, os assets e o fluxo serão reimplementados no Vorssaint; não serão
copiados arquivos da GPL-3.0 do Ice nem adicionada a dependência `AXSwift`.

## Problema e hipótese

Quando muitos apps registram itens, a pessoa perde acesso aos itens importantes e
não tem busca nativa. A hipótese a validar é que uma combinação de revelação rápida,
auto-rehide previsível e busca reduz a fricção sem exigir que o usuário mantenha
todos os itens permanentemente visíveis.

## Escopo do primeiro follow-up

### Incluído

- mostrar/ocultar a seção Hidden e, separadamente, Always Hidden;
- gatilho por botão do Vorssaint, atalho global, hover e clique em área vazia;
- gatilho por scroll/swipe como opção posterior dentro do mesmo contrato de eventos,
  somente se o monitor já usado pelo app puder ser reutilizado sem nova permissão;
- auto-rehide ao clicar fora ou após 3, 5, 10, 30 segundos e duração personalizada;
- não esconder enquanto um menu do item revelado estiver aberto ou a interação
  estiver em andamento;
- Menu Bar Search por atalho e comando na Command Bar, com revelação e ativação
  best-effort do item selecionado;
- espaçamento compacto, padrão, espaçado e valor limitado personalizado para os
  itens renderizados pela barra secundária e pelos divisores do organizador;
- backup e restauração das preferências não secretas;
- falhas de permissão, conflito com outro gerenciador e itens sem identidade estável
  explicados na UI, sem desligar outras features.

### Explicitamente adiado

- aparência da menu bar (tint, gradiente, sombra, borda, shape e transparência);
- perfis/layouts nomeados;
- grupos expansíveis;
- automações por app, VPN, bateria, microfone, monitor e Focus Mode;
- backend macOS 27 baseado em `MenuBarAgent`/AX por aplicativo;
- controle de menus do aplicativo à esquerda. É uma extensão de risco alto e deve
  ser uma decisão separada após o comportamento básico ser validado.

### Roadmap após o follow-up

| Fase | Entrega | Dependência/critério de saída |
|---|---|---|
| 2 | aparência opcional da barra e espaçamento avançado por superfície | MVP sem regressão visual em notched/externo; sem alterar menus de terceiros |
| 3 | perfis nomeados (Trabalho, VPN, Apresentação etc.) | ordem, seção, aparência e espaçamento versionados e restauráveis |
| 4 | grupos expansíveis e status do grupo | grupo não pode esconder item sem caminho individual de recuperação |
| 5 | regras condicionais por app, estado, bateria, microfone, monitor e Focus | motor de regras com debounce, explicação e fallback seguro |
| 6 | ocultação temporária de menus do aplicativo em conflito | prova em apps reais, restauração idempotente e permissão/limitação documentada |
| 7 | backend macOS 27 | investigação read-only, provider versionado, identidade AX verificada e aceitação em hardware real |

## Dependência, compatibilidade e segurança

- **Dependência de entrega:** PR #360 precisa estar integrada, ou o follow-up deve
  ser mantido como branch dependente até o mantenedor aceitar a sequência. Não abrir
  uma PR concorrente contra `upstream/main` com o mesmo núcleo.
- **macOS 14–26:** usar o provider do MVP e os limites de timeout/teardown já
  definidos por ele.
- **macOS 27+:** o recurso permanece inerte e mostra aviso localizado. Preferências
  são preservadas, sem probes do WindowServer e sem inicializar o serviço.
- **Privacidade:** nenhum conteúdo de menu, screenshot ou token sai do Mac. Logs
  usam identificadores técnicos não sensíveis e não registram títulos completos de
  itens quando não forem necessários para diagnóstico.
- **Dependências:** usar AppKit, CoreGraphics, ApplicationServices, Combine e
  SwiftUI já presentes. Não introduzir dependências externas.

## Histórias e critérios de aceitação

### História 1 — Revelação previsível

Como usuário, quero revelar itens Hidden e Always Hidden por ações configuráveis,
para acessar um item sem reorganizar a barra manualmente.

**Given/When/Then**

- Given o organizador está habilitado e a permissão necessária está concedida,
  When clico no botão do Vorssaint, Then Hidden alterna e a ordem observada pelo
  provider permanece intacta.
- Given Always Hidden está habilitado,
  When uso seu atalho ou a ação explícita “mostrar todos”, Then as duas seções
  aparecem sem mover nenhum item.
- Given hover, clique vazio ou scroll está desabilitado,
  When o evento ocorre, Then nada é revelado e o evento segue para o macOS.
- Given Accessibility foi revogada,
  When tento iniciar uma ação automática, Then o serviço é desmontado de forma
  idempotente e a UI mostra `PermissionRow`/orientação; outras features continuam.

### História 2 — Auto-rehide seguro

Como usuário, quero que itens revelados voltem a ser ocultados sem fechar menus ou
interromper cliques.

**Given/When/Then**

- Given auto-rehide está em 5 segundos,
  When a seção é revelada e não há interação, Then ela é ocultada após a duração
  sanitizada.
- Given um menu de um item revelado está aberto,
  When o timer vence, Then o rehide é adiado até o menu fechar e o ponteiro sair da
  área gerenciada.
- Given “ao clicar fora” está selecionado,
  When clico dentro do item, do menu ou da barra secundária, Then a seção fica
  visível; When clico fora, Then a seção é ocultada.
- Given o app perde foco durante a interação,
  When o estado não puder ser verificado com segurança, Then não há rehide forçado;
  uma nova mudança de foco reavalia o estado.

### História 3 — Busca de itens

Como usuário, quero localizar um item oculto pelo nome e ativá-lo.

**Given/When/Then**

- Given o snapshot contém um item estável,
  When digito parte do nome sem diferenciar maiúsculas ou acentos, Then o resultado
  é listado com a seção atual e estado de identidade.
- Given seleciono um resultado Hidden/Always Hidden,
  When confirmo, Then o serviço revela a seção, espera um snapshot novo e tenta
  clicar no mesmo window/item verificado.
- Given a identidade é provisória ou o item desapareceu,
  When confirmo, Then a busca mostra erro recuperável e não envia clique cego.
- Given não há resultados,
  When a busca está vazia, Then a interface explica que o item precisa estar
  registrado pelo macOS para aparecer.

### História 4 — Atalhos

Como usuário, quero configurar atalhos separados para revelar, esconder, buscar e
abrir a barra secundária.

**Given/When/Then**

- Given dois atalhos tentam usar a mesma combinação,
  When salvo o segundo, Then a UI aponta o conflito e não altera o primeiro.
- Given o atalho está desativado ou não pôde ser registrado,
  When o app inicia, Then o recurso segue utilizável pelos botões da UI e informa a
  falha sem travar o app.
- Given estou gravando um atalho,
  When a combinação de outra feature é pressionada, Then a gravação recebe a tecla
  e a feature anterior não é disparada.

### História 5 — Espaçamento

Como usuário, quero ajustar o espaçamento sem fazer a barra oscilar nem mover itens
de terceiros.

**Given/When/Then**

- Given compacto, padrão ou espaçado está selecionado,
  When a barra secundária é mostrada, Then o layout usa somente os valores
  sanitizados e mantém a ordem do snapshot.
- Given um valor personalizado está fora do limite,
  When salvo, Then ele é limitado ao intervalo suportado e o valor salvo é o
  sanitizado.
- Given o espaçamento muda,
  When um item está sendo clicado ou movido, Then a alteração não interrompe a
  operação em andamento; ela vale na próxima apresentação segura.

## Matriz de permissões e TCC

| Operação | Permissão/entitlement | Solicitação | Recusa | Teste manual Developer |
|---|---|---|---|---|
| Enumerar janelas/itens da menu bar | Accessibility para leitura/controle automático; APIs WindowServer já encapsuladas pelo MVP | Ao habilitar o organizador ou abrir a tela que precisa da ação | Manter serviço parado, permitir fallback informativo e mostrar `PermissionRow` | Build limpa `com.vorssaint.utils.dev` → negar → abrir Organizer → verificar instrução → conceder → voltar ao app → refresh |
| Command-drag/reordenar item | Accessibility + controle global de mouse | Somente ao editar/mover | Bloquear movimento automático; não enviar evento | Com permissão concedida, mover item estável entre as três seções e verificar pós-movimento |
| Atalho global Carbon | Não exige TCC por si só; conflito de registro é possível | Ao habilitar/configurar | Botões locais continuam funcionando; mostrar falha de registro | Salvar combinação ocupada e outra livre; verificar teardown ao desligar |
| Hover/clique/scroll global | Accessibility/event monitor conforme a API já adotada no app | Ao ativar o gatilho | Ignorar o gatilho e deixar o input seguir | Negar Accessibility e confirmar que não há interceptação nem crash |
| Busca/ativação | Accessibility para clicar item de outro app | Ao confirmar ativação, se ainda não concedida | Listar resultado, mas explicar que ativação exige permissão | Buscar item estável, oculto, provisório e removido |
| Barra secundária | Nenhuma nova permissão; janela não ativadora | Quando solicitada | Fallback para a menu bar ou mensagem de indisponibilidade | Notch, monitor externo, mudança de tela, Spaces e auto-hide |
| Screen Recording | Não usar no MVP/follow-up | Nunca solicitar para organizer | N/A | Confirmar que habilitar o organizer não altera o estado de Screen Recording |

O bundle Developer tem consentimento TCC próprio (`com.vorssaint.utils.dev`) e deve
ser usado nos testes. O estado não deve ser inferido da instalação oficial.

## Dados persistidos

Preferências novas, sem segredos:

- habilitação de cada gatilho;
- ação de revelar/esconder e política de auto-rehide;
- duração personalizada dentro de limites;
- atalhos como `GlobalShortcut.storageValue`;
- preset de espaçamento e valor customizado.

Os IDs/ordem dos itens permanecem sob o contrato do MVP, aceitando manifests antigos
e descartando identidades provisórias. O backup deve incluir somente preferências,
não window IDs, PID, posição momentânea, snapshot, cache de imagem ou estado ativo.

## Métricas de sucesso local

Sem telemetria remota. Validar por roteiro manual:

1. reduzir itens permanentes sem perder acesso aos essenciais;
2. encontrar e ativar um item de terceiro em menos interações que navegar por todos
   os itens revelados;
3. não fechar menus abertos nem deixar o cursor preso após auto-rehide;
4. manter comportamento das demais features com organizer desligado, sem Accessibility
   e em macOS 27+.

## Riscos e decisões abertas

- O macOS 27 mudou o modelo de composição da barra; não ampliar o backend antes de
  uma investigação separada e read-only.
- Itens hospedados por Control Center podem não ter identidade estável. Resultados
  provisórios devem ser pesquisáveis, mas não clicáveis/movíveis automaticamente.
- Apps que recriam seus status items podem mudar ocorrência/identidade. O provider
  deve fazer refresh e não “consertar” posição com uma suposição perigosa.
- Menus do aplicativo à esquerda e aparência da barra têm risco de conflito visual;
  ficam fora deste slice.

---
status: in-progress
baseline_commit: 97f6f43
---

# Story 2.4 — Descoberta confiável e editor legível

Epic: Epic 2 — Descoberta e densidade  
Branch: `feat/menu-bar-manager-followup`  
Worktree: `/Users/ruansantana/Documents/DeepAgent/vorssaint-utils-menu-bar-manager`

## Problema observado

Em macOS 26, a sonda privada do WindowServer pode retornar só parte dos status
items. O editor passa a mostrar poucos itens, incluindo divisores internos do
Vorssaint, e usa identificadores de Accessibility como
`Vorssaint.MenuBarOrganizer.control` como título visível.

## História

Como usuário, quero ver os ícones reais da barra de menus com nomes curtos e
editáveis, para organizar apenas o item que escolhi sem depender de identificadores
técnicos ou de uma enumeração incompleta.

## Critérios de aceitação

1. A enumeração une candidatos da lista privada e da enumeração pública segura do
   WindowServer; uma lista privada parcial não remove itens públicos válidos.
2. Os divisores gerados pelo Organizer nunca aparecem como itens editáveis, mesmo
   enquanto o AppKit ainda não fornece o `windowID` do divisor.
3. `AXIdentifier` continua sendo usado para identidade estável, mas não é mostrado
   como título humano; o editor prefere título acessível e nome do app.
4. Itens sem fonte resolvida continuam visíveis com ícone/nome de fallback e ficam
   bloqueados até que sua identidade possa ser verificada.
5. Cada pill limita o texto, preserva o ícone e mantém o tooltip com o nome completo.
6. Testes cobrem união de candidatos, filtragem dos divisores, títulos técnicos e
   preservação da identidade estável.

## Limites

- Usar o Thaw somente como referência pública de comportamento e separação entre
  app principal, WindowServer e Accessibility. Não copiar código, dependências,
  assets, textos ou nomes internos do projeto.
- Não solicitar Screen Recording; descoberta e movimentação seguem o contrato de
  Accessibility já usado pelo Vorssaint.
- Itens provisórios não são arrastáveis até que a origem seja resolvida.

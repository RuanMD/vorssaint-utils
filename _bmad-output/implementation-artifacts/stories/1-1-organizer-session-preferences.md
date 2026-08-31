# Story 1.1 — Modelo de sessão e preferências do Organizer

Status: implemented
Epic: Epic 1 — Reveal seguro e auto-rehide
Branch: feat/menu-bar-manager-followup
Base/dependência: PR #360 (`upstream/pr-360`)

## História

Como usuário, quero que o Organizer tenha estados e preferências previsíveis,
para que revelar, esconder e reiniciar o app não alterem minha organização.

## Critérios de aceitação

1. Given uma configuração inválida, When ela é carregada, Then cada enumeração,
   duração e espaçamento é sanitizado para um valor seguro e persistível.
2. Given Hidden e Always Hidden, When uma seção é revelada, Then a outra mantém
   seu estado e a ordem/identidade dos itens não é modificada.
3. Given uma versão antiga do backup, When ela é importada, Then defaults novos
   são usados sem apagar preferências não relacionadas.
4. Given macOS 27+, When o app inicia, Then as preferências são preservadas e o
   provider não é inicializado.
5. Given uma regra pura, When MetricsTests a executa, Then o resultado não depende
   de AppKit, relógio real, Accessibility ou estado global.

## Tarefas

- [x] Criar modelos puros para triggers, rehide e spacing.
- [x] Adicionar DefaultsKey/registered defaults com migração compatível.
- [x] Cobrir sanitização, estados, backup e macOS gate em MetricsTests.
- [x] Atualizar File List e notas de implementação.

## Arquivos prováveis

`Sources/Vorssaint/Core/`, `Sources/Vorssaint/Services/MenuBarOrganizer/`,
`Tests/MetricsTests.swift`.

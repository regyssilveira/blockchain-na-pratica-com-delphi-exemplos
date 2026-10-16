# Dependências de terceiros

As revisões exatas estão em `dependencies.lock.json`. Preservar os arquivos de licença dos checkouts obtidos.

| Projeto | Licença principal | Uso |
|---|---|---|
| Xor-el/CryptoLib4Pascal | MIT | Criptografia e suíte original DUnit |
| Xor-el/HashLib4Pascal | MIT | Hashes e suíte original DUnit |
| Xor-el/SimpleBaseLib4Pascal | MIT | Codificações e suíte original DUnit |
| VSoftTechnologies/DUnitX | Apache 2.0 | Executor original; teste de duração corrigido e ampliado pelo patch regional identificado no README |
| VSoftTechnologies/Delphi-Mocks | Apache 2.0 | Dependência da suíte DUnitX; patch mínimo de importação descrito no README e no script de preparo |

Não são redistribuídos fontes ou bibliotecas proprietárias do Delphi. A licença Apache dos exemplos não altera os termos dos componentes de terceiros. O contrato e o cliente blockchain ainda não foram escritos.

Os vetores de P03 foram produzidos na autoria com ethers 6.15.0 (MIT, Richard Moore), obtido do pacote oficial e com integridade conferida. O pacote e seu runtime não são redistribuídos nem usados pelo executável Delphi. Dados gerados e referências normativas estão documentados em fixtures/p03/PROVENIENCIA.md.

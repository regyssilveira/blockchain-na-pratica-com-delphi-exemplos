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

## Anvil / Foundry 1.8.5 — ferramenta externa de desenvolvimento

Código principal: MIT OU Apache-2.0, projeto foundry-rs/foundry, commit 51a52c59cffd940f76eddd0b4bb1791aa4b5ac7f. O leitor baixa o pacote oficial por Prepare-Anvil.ps1; não há binários Foundry versionados ou redistribuídos aqui. Dependências transitivas do pacote mantêm seus próprios termos. A utilização local validada não declara auditoria integral dessas licenças. Veja a release oficial e o inventário de ambiente do livro.

## Solidity / solc 0.8.37 — compilador externo

Compilador oficial 0.8.37+commit.f401782d, fonte na revisão f401782df49be312ea4ef52a2d467cf5183b5906. O arquivo LICENSE.txt dessa versão contém a GNU General Public License versão 3: https://github.com/argotorg/solidity/blob/v0.8.37/LICENSE.txt . Build-Contract.ps1 baixa separadamente o executável oficial e confere seu SHA-256; não há executável solc distribuído neste repositório. O contrato DocumentRegistry.sol é fonte original deste exemplo, sob Apache-2.0, identificada no cabeçalho. Compilador, fonte do contrato e artefato gerado são materiais distintos. O manifesto da compilação e seus resultados ficam documentados em validation/2026-10-16-p04-contract/RESULTADOS.md. Não se declara revisão integral de licenças transitivas do compilador.

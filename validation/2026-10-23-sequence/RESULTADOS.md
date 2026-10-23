# Sequência dos capítulos 15 e 17 — 23/10/2026

Correção documental: selecionar a revisão antes do primeiro exercício. A tag `reading-revision-2026-10-23` permanece fixa; não houve alteração de fontes Delphi, dependências, contrato ou testes.

## Conferências executadas

- Cópia Git isolada, em caminho com espaços: transições da tag dos capítulos 14/16 para a revisão de leitura; arquivos ausentes antes e presentes depois do checkout; comando de seleção antes do primeiro roteiro em ambos os capítulos. Os roteiros executados no checkout principal são idênticos aos da tag. O clone isolado conferiu a seleção de fontes; não foi uma nova compilação limpa nem uma nova obtenção de todas as dependências pela internet.
- `Test-Chapter15.ps1`, Delphi 13 Win64, Windows PowerShell 5.1, porta 20045: consulta 31337, argumento ausente e nó encerrado aprovados.
- `Test-ReadingRevision.ps1`: 114 testes existentes, zero falhas/erros/ignorados; bloco, causas isoladas, busca, rastreamento, outro arquivo, caminho ausente e SHA-256 independente aprovados. Nenhuma transação enviada pelo rastreamento.
- `Test-Prototype.ps1`, porta 19245: 108 testes existentes, implantação/registro/consulta, 13 operações em processos e falha com nó encerrado aprovados. Os totais de 114 e 108 se sobrepõem e não devem ser somados.
- `Test-Chapter14.ps1`: inspeção de ambiente e erros esperados aprovados após encerramento do roteiro de integração.

Uma tentativa de iniciar o preparo do capítulo 14 enquanto a integração ainda utilizava o executável Anvil falhou por arquivo em uso. Foi erro de paralelização desta validação: o preparo reextrai a ferramenta no mesmo caminho. O roteiro foi repetido sequencialmente com sucesso; essa tentativa não foi contada como aprovação. Os roteiros que compartilham `build/tools` devem ser executados um de cada vez.

Os JSON anexos são observações desta rodada. Caminhos locais identificam o ambiente observado e não são comandos portáveis. Anvil e dependências foram preparados a partir dos caches locais verificados; esta rodada não comprova um primeiro download em máquina vazia. As instruções dos READMEs mostram como obter e selecionar os fontes antes da execução.

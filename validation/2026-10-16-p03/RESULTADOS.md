# Validação local de Keccak, ABI, RLP e assinatura

Em 16/10/2026, `scripts/Test-Protocol.ps1` compilou e executou Protocol.Tests.exe em Delphi 13 Win64, build 37.0.57242.3601: **76 testes aprovados, zero ignorados, falhas ou erros**, código de saída zero. O conjunto reúne os 44 testes de P02 e 32 novos cenários de P03. Não foi necessário nó, carteira de navegador, provedor, Node.js ou Python para executar os testes Delphi.

## Verificações executadas

| Área | Evidência observada |
|---|---|
| Keccak-256 | Quatro vetores independentes; digest do vazio conferido explicitamente; distinção entre Keccak-256 e SHA3-256 |
| ABI | Seletores e chamadas completas coincidem com a referência em três casos; palavras uint256, bool, address e bytes32; leitura estrita de bool e address; rejeição de padding e tamanhos inválidos |
| RLP | Doze vetores coincidentes, com dados/listas vazios, bytes unitários, listas aninhadas e transições de comprimento curto/longo; zero inteiro distinguido do byte zero |
| ECDSA | Assinatura determinística no digest de 32 bytes, r/s/paridade conferidos contra referência EIP-155 e implementação independente |
| Canonização | Normalização para s baixo exercitada com caso que a biblioteca originalmente assinou com s alto; resultado permanece verificável; s alto recebido é rejeitado |
| Recuperação | Chave e endereço recuperados coincidem com o remetente da referência; ambas as paridades são exercitadas nos vetores tipo 2 |
| Transação tipo 2 | Três envelopes sem assinatura, digests, assinaturas, bytes completos assinados e identificadores coincidem byte a byte com a referência independente |
| Adulterações | Digest ou paridade alterados falham na verificação contra a chave esperada; mudanças em chainId, nonce e dados alteram o digest de assinatura |
| Entradas inválidas | Chave ausente, zero ou igual à ordem; digest com tamanho errado; r zero; s alto; paridade fora de 0/1; destino malformado; prioridade acima da taxa máxima e chainId zero no modelo local |

Os vetores tipo 2 usam chainId 1 e 31337, nonce zero e 128, valor zero e não zero, dados vazios e de chamada, destino de 20 bytes e destino vazio. Os parâmetros de criação são somente um envelope de teste; o bytecode, limite de execução e taxas não foram aceitos por uma máquina virtual nesta etapa.

## Implementação nativa

`src/Blockchain.Ethereum.pas` usa HashLib4Pascal para Keccak e CryptoLib4Pascal para ECDSA, HMAC determinístico, inteiros e operações de curva secp256k1. A integração não reimplementa adição/multiplicação de pontos ou primitivas de assinatura. SHA-256 é usado pelo gerador determinístico de nonce RFC 6979; o digest da transação continua sendo Keccak-256, sem prefixo de mensagem pessoal e sem aplicar um segundo hash à mensagem já resumida.

A recuperação combina operações da biblioteca segundo a assinatura e o digest. O assinador procura a paridade compatível com a chave depois de normalizar s. Se o caso raro do ponto efêmero com coordenada x maior ou igual à ordem não puder ser representado apenas por yParity, ele interrompe explicitamente; não produz assinatura silenciosamente inválida nem implementa geração alternativa de nonce. Este caso raro não foi forçado nos testes.

A primeira execução compilada teve dois erros de acesso durante a verificação ECDSA auxiliar. A implementação foi corrigida para manter os parâmetros de domínio e chave pública em interfaces locais e usar o construtor com algoritmo explícito. Após a alteração, todos os testes passaram. Não foi atribuída uma causa isolada à biblioteca, nem alterado qualquer fonte de terceiro para resolver esses erros.

## Reprodução

```powershell
.\scripts\Test-Protocol.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

O script reutiliza o preparo e o executor de P02, selecionando o projeto Protocol. Compila com caminhos explícitos e `--no-config`, executa com prazo de 60 segundos e exige XML sem falhas, erros ou ignorados. Outputs em build/Protocol: compile.log, compiler-arguments.txt, tests.log, tests.stderr.log, results.xml e summary.json. O comando Test-Primitives.ps1 sem -Protocol continua executando apenas P02.

As referências prontas e sua procedência estão em fixtures/p03. Sua criação por uma ferramenta independente na autoria não cria uma ponte de assinatura no cliente: os bytes assinados e a recuperação durante os testes são calculados no executável Delphi. Nenhum programa JavaScript é necessário ao leitor.

## Limites e continuidade

O ABI implementado é um conjunto de construtores de palavras e chamadas estáticas. O chamador fornece a assinatura canônica e as palavras conhecidas; não há parser de JSON ABI, normalização de aliases, conferência genérica de aridade ou tipos dinâmicos. RLP oferece codificadores de bytes, inteiros e listas de itens já codificados; não é um decodificador ou validador de payload RLP recebido. A transação suporta somente lista de acesso vazia e o formato tipo 2. A exigência de chainId positivo é uma regra explícita do laboratório.

Os testes anteriores das dependências completas não foram repetidos, pois suas revisões e fontes não mudaram. P02 foi executado novamente dentro do projeto combinado, por ser utilizado pelos componentes novos.

P03 está validado para esses vetores e esse ambiente. A parte de V11 referente a codificação, precisão, assinatura e recuperação offline foi exercitada; a aceitação do remetente e do envelope por um nó, a implantação, os recibos e as falhas de rede permanecem pendentes. Não há conclusão de segurança de produção, custódia, desempenho ou compatibilidade com outras plataformas.

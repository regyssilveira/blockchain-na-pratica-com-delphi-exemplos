# Formato e regras da blockchain didática

Esta especificação descreve o protocolo próprio implementado em `src/Didactic.*.pas`. A codificação binária é a entrada do hash; JSON é somente transporte e persistência. Não é o protocolo Ethereum. Reutilizam-se as funções Delphi de curva secp256k1 de `Blockchain.Ethereum`, com digest SHA-256 neste modelo.

## Bytes canônicos

Inteiros binários são sem sinal, em ordem big-endian. `text(s)` significa comprimento UTF-8 em 4 bytes, seguido dos bytes UTF-8. Hexadecimal no JSON é minúsculo, sem prefixo, com comprimento exato. Inteiros JSON são strings decimais canônicas: somente dígitos, sem zeros iniciais exceto `0`, sem sinais, expoentes ou frações. Rejeitam-se campos desconhecidos, ausentes ou duplicados. A ordem das propriedades JSON não altera o hash.

Transação: `text(DIDACTIC-TX-1)`, `text(network)`, chave pública não comprimida de 65 bytes, hash do documento de 32 bytes, sequência em 8 bytes. Assina-se SHA-256 dessa sequência binária com secp256k1, assinatura determinística, S baixo e paridade de recuperação. Acrescentam-se R em 32 bytes, S em 32 bytes e paridade em 1 byte. O identificador é SHA-256 de todos esses bytes assinados. A conta é SHA-256 dos 65 bytes da chave pública.

JSON da transação contém exatamente `network`, `publicKey`, `documentHash`, `sequence`, `r`, `s`, `parity`. Conta e identificador são derivados, nunca fornecidos como autoridade pelo remetente.

Bloco: `text(DIDACTIC-BLOCK-1)`, `text(network)`, altura em 8 bytes, hash anterior em 32 bytes, instante lógico em 8 bytes, dificuldade em 1 byte, nonce em 8 bytes, quantidade de transações em 4 bytes; para cada transação, comprimento em 4 bytes e bytes assinados. O hash é SHA-256 desse conjunto. A prova exige a quantidade definida de zeros hexadecimais iniciais. JSON contém `height`, `previousHash`, `timestamp`, `difficulty`, `nonce`, `transactions`, `hash`.

## Rede e estado

Identificação `delphi-didactic-v1-d2` para dificuldade 2; aceitam-se também redes separadas d3 e d4. O bloco inicial fixo tem altura e instante zero, hash anterior zero, nenhuma transação e nonce definido nos vetores independentes. Rede, dificuldade e bloco inicial precisam coincidir; não se muda a dificuldade no meio da cadeia.

Cada transação precisa de assinatura válida, rede correta, sequência consecutiva da conta a partir de 1 e par conta/documento ainda não registrado. A repetição exata de uma transação conhecida é idempotente; transações diferentes com sequência conflitante são rejeitadas. Cada bloco posterior ao inicial contém de 1 a 8 transações, altura consecutiva e instante estritamente crescente.

Trabalho acumulado exclui o bloco inicial e soma `16^dificuldade` por bloco. Como a dificuldade é fixa na rede, equivale a comparar alturas válidas. Empate conserva a história local. Uma história concorrente só é adotada depois de validar todos os blocos e reconstruir o estado. Transações órfãs ainda válidas retornam ao conjunto pendente; conflitos de sequência são descartados. Campos de trabalho anunciados por um par não substituem o cálculo local.

## Persistência e limites

Máximos: 128 blocos incluindo inicial, 8 transações por bloco, 64 pendentes, snapshot de 2 MiB, 8 pares e dificuldade de 2 a 4. Mineração tem limite de tentativas e tempo. O protocolo HTTP aceita requisições de tamanho limitado e Content-Length, sem transferência fragmentada. Todas as conexões ficam em loopback.

O snapshot contém esquema, rede, dificuldade, blocos e pendentes. O envelope contém esquema 1, SHA-256 dos bytes UTF-8 do payload e o payload como string JSON. Carregar exige checksum e validação integral. Gravar usa arquivo temporário próprio, flush e substituição Windows; a mudança só é publicada em memória depois de salvar. Isso não promete durabilidade contra qualquer falha de hardware.

O servidor serializa as mudanças no estado. Um trabalhador separado troca mensagens e enfileira respostas; não modifica a cadeia. A sincronização transfere uma cadeia limitada inteira e a valida localmente. Não há descoberta pública de pares, incentivos, escolha dinâmica de dificuldade, consenso de produção nem compatibilidade de fio com Ethereum.

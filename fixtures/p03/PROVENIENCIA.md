# Referências independentes de protocolo

Vetores criados em 16/10/2026 com ethers 6.15.0, implementação independente das bibliotecas Pascal. O pacote oficial foi obtido em https://registry.npmjs.org/ethers/-/ethers-6.15.0.tgz e teve seu SHA-512 conferido com a integridade publicada no registro. Versão, endereço, checksum do pacote e SHA-256 de reference.json estão em provenance.json.

O pacote, seu runtime e o gerador foram usados somente na autoria, em build/reference-p03, ignorado pelo Git. Não integram o cliente Delphi nem são requisitos do leitor. O executável nativo lê os vetores prontos sem gerar seus resultados esperados. Não foi copiado código de implementação do ethers para os exemplos.

reference.json contém:

- Quatro entradas e saídas de `keccak256`, incluindo vazio e `abc`.
- Doze árvores de entrada e saídas de `encodeRlp`, incluindo bytes/listas vazios, valores unitários, listas aninhadas e limites de 55/56 bytes.
- Três chamadas ABI, com seletor calculado por `id(signature)` e palavras por `AbiCoder.defaultAbiCoder().encode(types, values)`.
- Três transações tipo 2: transferência, dados de uma chamada de registro e envelope de criação com dados ilustrativos. Foram construídas com `Transaction.from`, assinadas por `Wallet.signTransaction` e analisadas novamente com `Transaction.from(raw)`. Foram preservados envelope sem assinatura, digest de assinatura, r, s, paridade, bytes assinados, identificador e remetente recuperado.
- A assinatura do digest publicado no exemplo EIP-155. Essa conferência não implementa nem valida a serialização de transações legadas; apenas ancora a assinatura em um segundo vetor publicado.

A chave privada de teste `46` repetida 32 vezes é publicamente conhecida no exemplo EIP-155. O endereço esperado é `0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f`. Não foram usados segredos do autor ou contas reais. Todos os vetores são offline: nenhum saldo ou transação foi enviado a uma rede.

Fontes primárias consultadas:

- [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559): envelope 0x02, campos e digest de assinatura.
- [EIP-155](https://eips.ethereum.org/EIPS/eip-155): digest, chave e componentes da assinatura do exemplo legado.
- [EIP-2](https://eips.ethereum.org/EIPS/eip-2): restrição de s baixo em assinaturas de transações.
- [RFC 6979](https://www.rfc-editor.org/rfc/rfc6979): geração determinística do nonce pela biblioteca.
- [Especificação ABI](https://docs.soliditylang.org/en/latest/abi-spec.html): palavras estáticas e exemplo baz(uint32,bool). Nesse exemplo, a palavra inteira é codificada como uint256 porque o valor 69 tem a mesma representação estática; o laboratório não oferece validação genérica de todos os tamanhos uint.
- [RLP](https://ethereum.org/developers/docs/data-structures-and-encoding/rlp/): codificação de bytes e listas.
- [ethers](https://github.com/ethers-io/ethers.js), MIT: implementação independente usada na autoria dos vetores.

As referências são dados de teste gerados para este projeto. Não certificam segurança do cliente e não substituem a execução contra nó em P04/P05.

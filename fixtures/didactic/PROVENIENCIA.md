# Procedência dos vetores didáticos

Os vetores são referências fixas independentes da implementação Delphi. O bloco inicial foi calculado com Python hashlib SHA-256 e inteiros big-endian. A transação e o bloco com documento foram calculados com Node crypto e ethers 6.15.0 (MIT), usando a mesma distribuição já documentada em fixtures/p03/PROVENIENCIA.md. São ferramentas de autoria, não dependências do leitor. Os testes leem somente os JSON e comparam bytes, digest, assinatura determinística, identificador, nonce e hash.

- `genesis-reference.json`: SHA-256 `1397fe7947a4a6c5645ac95c15087c786117f011d63b1ece40cd4bfcb3cdb9d5`.
- `transaction-reference.json`: SHA-256 `f84b9419a42fdf1f23ab72132106a0ba08b61ce3cbe0374f15144ecef7243cd5`.

Os arquivos JSON preservam LF por .gitattributes. Chave privada de referência: inteiro 1 em 32 bytes, publicamente conhecido. Não usar em produção. O formato próprio está em chapters/part03/PROTOCOL.md.

# Entradas e referências independentes de P02

Arquivos criados em 16/10/2026. Os textos não contêm marcador de ordem de bytes (BOM) nem quebra de linha final. document-a.txt e sua cópia contêm `Certificado de exemplo 001`; document-b.txt troca somente o último byte por `2`. Os arquivos têm 26 bytes. empty.bin tem zero bytes, abc.txt tem os três bytes ASCII de `abc`, utf8.txt contém os bytes `61 c3 a7 c3 a3 6f` e binary.bin contém `00 ff 80 01 0d 0a 00`.

Os arquivos bytes-N.bin têm N bytes, com o byte de índice i igual a i módulo 256, para N em 55, 56, 63, 64, 65 e 4097. Isso cobre as proximidades do preenchimento do SHA-256 e dados com vários blocos. Não é teste de arquivo maior que 4 GiB ou de desempenho.

sha256-reference.json preserva tamanho, conteúdo hexadecimal e digest completo de cada arquivo. As referências foram calculadas antes dos testes Delphi com `System.Security.Cryptography.SHA256.Create().ComputeHash(byte[])`, do .NET, e gravadas como dados fixos. A cadeia vazia e `abc` foram também conferidos contra seus digests conhecidos. Não foi copiado código de implementação criptográfica externa. Os testes Delphi confrontam os mesmos resultados fixos com a biblioteca padrão e com HashLib4Pascal, implementações separadas.

numeric-reference.json registra a conversão independente dos sete valores decimais de teste por System.Numerics.BigInteger, com representação hexadecimal sem sinal e palavra de 32 bytes. O sinal extra que ToString("x") pode acrescentar foi retirado somente dessa representação de referência; o valor zero foi mantido como `0`. Os mesmos pares decimal/hex estão explícitos nos casos de teste Delphi. A conferência da igualdade entre os pares foi feita na preparação dos dados; o JSON numérico é evidência complementar.

O .NET foi ferramenta de autoria das referências, não dependência da implementação ou do executável de testes Delphi. O leitor recebe as referências prontas e executa testes nativos sem gerar os resultados esperados novamente. PowerShell e Git servem à preparação e à automação. As entradas foram criadas para este projeto e são distribuídas sob a licença Apache 2.0 dos exemplos.

As regras de quantidade com prefixo `0x`, zero como `0x0` e ausência de zeros iniciais seguem a [documentação oficial de JSON-RPC Ethereum](https://ethereum.org/developers/docs/apis/json-rpc/#hex-value-encoding). O limite de 256 bits e a entrada decimal estrita são escolhas do tipo TExactUInt256 deste laboratório, não restrições universais de todo método JSON-RPC. Não confundir palavra fixa de 32 bytes com quantidade hexadecimal compacta.

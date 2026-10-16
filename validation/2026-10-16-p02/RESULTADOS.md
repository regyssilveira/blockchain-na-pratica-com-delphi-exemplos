# Validação de hashes, bytes e precisão numérica

Em 16/10/2026, os testes de `tests/Primitives.Tests.dpr` compilaram em Delphi 13 Win64, build 37.0.57242.3601, e executaram localmente: **44 aprovados, zero ignorados, zero falhas e zero erros**, código de saída zero. As bibliotecas mantêm as revisões fixadas em dependencies.lock.json. Não houve uso de nó, internet no executável, carteira, chave privada ou serviço externo.

## Escopo observado

| Área | Verificação |
|---|---|
| Integridade de arquivos | Documento A e cópia têm digest idêntico; alteração de um byte produz digest diferente |
| Referências fixas | 13 arquivos confrontados com tamanho, bytes e SHA-256 pré-calculados; biblioteca padrão e HashLib4Pascal concordam com a referência independente |
| Limites de blocos | Arquivos de 55, 56, 63, 64, 65 e 4097 bytes |
| Codificação | UTF-8 explícito; formas Unicode distintas, LF/CRLF e presença de BOM não são normalizadas |
| Hexadecimal | Hash de documento tem exatamente 32 bytes e 64 dígitos sem prefixo; zeros e bytes de bit alto são preservados; caracteres e tamanhos inválidos são rejeitados |
| Arquivo ausente | Erro de abertura explícito; arquivo vazio permanece entrada válida |
| Precisão | 0, 1, 255, 256, 2^53+1, 2^64 e 2^256−1 preservados em decimal, quantidade hexadecimal e palavra big-endian de 32 bytes |
| Limites | 2^256 é rejeitado em decimal e hexadecimal; sinal, fração, expoente, espaços, formatos não canônicos e palavras com 31/33 bytes são rejeitados |
| JSON | Quantidade é transportada como string; 2^53+1 sobrevive à serialização e leitura sem conversão a ponto flutuante |

TExactUInt256 usa TBigInteger da CryptoLib4Pascal. A palavra fixa usa sinal positivo explícito e ordem do byte mais significativo primeiro. SHA-256 usa System.Hash, sem implementar primitivas criptográficas. O parser decimal aceita apenas dígitos e não admite zeros à esquerda, exceto no zero; essa é uma convenção local documentada. A quantidade JSON-RPC e o hash de documento têm formatos distintos.

Entradas, resultados esperados e procedência estão em `fixtures/p02/PROVENIENCIA.md` e nos dois arquivos JSON de referência. O arquivo de SHA é lido pelo teste; o JSON numérico preserva a conferência independente dos pares literais dos casos de teste. O executável é nativo Delphi; a ferramenta .NET usada para produzir referências na autoria não faz parte dos cálculos em teste.

## Repetição local

```powershell
.\scripts\Test-Primitives.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

O script obtém/confere dependências, chama o compilador por caminho explícito, compila fontes em build/Primitives, executa com limite de 60 segundos e exige XML sem falhas, erros ou ignorados. Não confia apenas no código do processo. Saídas: compile.log, compiler-arguments.txt, tests.log, tests.stderr.log, results.xml e summary.json. Os arquivos de referência têm conversão de quebras de linha desativada pelo .gitattributes.

## Relação com os critérios do protótipo

- V01: atendido para as entradas e referências definidas.
- V06: atendido somente para arquivo ausente e validações locais de hashes e números; configuração de rede e rejeição no contrato continuam pendentes.
- V11: precisão e conversões atendidas para os valores exercitados; assinatura, remetente, identificador de rede e transação tipo 2 ainda não foram validados.

Não foram repetidas as suítes completas de terceiros, pois seus fontes e revisões não mudaram. Esta execução exercitou as unidades necessárias ao P02 no novo executável. Não comprova assinatura Ethereum, consenso, segurança de produção ou compatibilidade com outros compiladores e plataformas.

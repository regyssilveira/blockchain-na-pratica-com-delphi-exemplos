# Transações e estado em memória

`demos/Chapter07.Transactions.dpr` compõe TDocumentTransaction e TDidacticState já validados. Não implementa novas regras de assinatura, sequência ou cadastro. O modelo registra pares conta/hash e mantém sequência por conta. O console não constrói blocos nem inicia nós; apenas aplica regras em memória e reconstrói as consultas a partir de três transações aceitas.

## Repetir localmente

Requisitos: Windows x64, Delphi 13 Win64 instalado/licenciado, PowerShell 5.1 ou 7 e Git. O primeiro preparo obtém os fontes fixados de dependencies.lock.json. Código original Apache-2.0; dependências mantêm as licenças de THIRD_PARTY_NOTICES.md. Não requer Anvil, solc, carteira, Node.js ou Python.

```powershell
git checkout chapter07-examples-2026-10-16
.\scripts\Test-Chapter07.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

O roteiro executa 114 testes existentes (76 offline P02/P03 + 38 casos da base didática), incluindo regressões de blocos e mineração em memória. Depois compila e executa 14 verificações em um console, distintas dos cenários de múltiplos nós da Parte 3. Não são 114 novos testes de transações.

```text
validacao_sem_aplicacao=True
primeiro_registro=True
formato_invalido_rejeitado=True
adulteracao_rejeitada=True
reenvio_rejeitado=True
sequencia_reutilizada_rejeitada=True
salto_rejeitado=True
documento_duplicado_rejeitado=True
outra_rede_rejeitada=True
estado_apos_rejeicoes_preservado=True
mesmo_documento_outra_conta=True
proxima_sequencia=True
reconstrucao_do_estado=True
ordem_invertida_rejeitada=True
```

True significa que a condição esperada foi observada, inclusive a rejeição. Conferir interrompe o processo se uma condição for falsa. Os erros de argumentos ausentes, arquivo inexistente e conteúdos iguais devem produzir saída 1. Uma expiração de prazo não aprova o experimento. Resultados locais: build/Didactic e build/Chapter07.Transactions.

## Entradas e limites

```powershell
.\build\Chapter07.Transactions\Chapter07.Transactions.exe '.\fixtures\p02\document-a.txt' '.\fixtures\p02\document-b.txt'
```

O console aceita dois caminhos, mas exige hashes distintos para demonstrar próximo documento e duplicidade separadamente. Usa chaves privadas com valores publicados: inteiros 1 e 2 em 32 bytes. Nunca substituir por segredo real. A conta deste modelo é SHA-256 da chave pública não comprimida; não é endereço Ethereum. Não existe cadastro de emissores autorizados nem verificação da verdade do documento.

As regras de negócio são sequência consecutiva a partir de 1 por conta, identificador não reaplicado e ausência do mesmo par conta/hash. A mesma solicitação pode passar em Validate e falhar em Apply por causa do estado. O estado observado permanece em A/1 durante as recusas; depois são aplicadas B/1 para o primeiro documento e A/2 para o segundo. O histórico em array contém A/1, B/1, A/2. A reconstrução confere as consultas e sequências; tentar começar por A/2 é rejeitado.

Apply recebe BlockHeight=1 como metadado sintético deste exercício. Nenhum bloco é criado ou demonstrado por esse número. O array local não é persistência protegida, confirmação, prova de tempo ou histórico distribuído.

O componente de estado rejeita reaplicar um identificador. Isso é diferente do método Submit da cadeia completa, que reconhece reenvio exato e retorna False sem incluir novamente no conjunto pendente. O console testa aplicação ao estado, não envio à rede. [Resultados executados](../../validation/2026-10-16-chapter07/RESULTADOS.md).

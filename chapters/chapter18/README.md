# Aplicação VCL de registro e verificação

Referência técnica: tag `chapter18-examples-2026-10-16`. Código original Apache License 2.0. Requer Windows x86-64 e Delphi 13 Win64 instalado e licenciado, Git e Windows PowerShell 5.1 (ou PowerShell 7). O primeiro preparo baixa dependências e ferramentas fixadas; não exige Node.js, Python, Docker, carteira ou provedor externo. Nenhum executável Delphi ou de terceiros é distribuído.

## Validar localmente

Na raiz do repositório:

```powershell
.\scripts\Test-Chapter18.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0' -Port 19345
```

O roteiro completo executa as 108 regressões do protótipo na porta seguinte, compila o programa de aceitação e a aplicação VCL, inicia outra instância própria do Anvil, confere 28 condições do fluxo, testa a janela e encerra o nó. Em seguida exige falha explícita ao acompanhar com o nó real encerrado. Ambas as portas precisam estar livres. A opção `-SkipPrototype` serve somente à investigação incremental; não significa que as 108 regressões foram executadas.

`build/Chapter18/latest.json` aponta para a pasta desta execução. Ela conserva `acceptance.json`, `ui-acceptance.json`, `resume-check.json`, `stopped-ui.json` e logs. São verificações de aceitação, não novos testes DUnitX. A janela é criada em modo de autoteste oculto; um timer real continua processando eventos durante espera pendente de três segundos. O teste envia uma mensagem de fechamento e confere adiamento, controles desabilitados durante o trabalho, atualização na thread principal, liberação do trabalhador e hash preservado. Outro processo confirma que não surgiu um novo envio. Isso não substitui avaliação visual/manual da interação com os diálogos de arquivo.

## Usar a janela

O roteiro de testes encerra sua rede. Para usar a aplicação, mantenha uma instância nova aberta em um terminal, na raiz:

```powershell
& '.\build\tools\anvil\anvil.exe' --host 127.0.0.1 --port 19345 --chain-id 31337 `
  --hardfork cancun --accounts 0 `
  --fund-accounts 0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f:100 `
  --block-base-fee-per-gas 1000000000 --no-mining
```

Em outro terminal, também na raiz:

```powershell
& '.\build\Chapter18.Desktop\Chapter18.Desktop.exe' 19345
```

1. Clique em **Implantar contrato** e escolha um arquivo JSON novo de acompanhamento. Aguarde a resposta de envio.
2. Gere um bloco no terminal do cliente: `& '.\build\DocumentRegistry.Cli\DocumentRegistry.Cli.exe' mine 19345`.
3. Clique em **Acompanhar implantação**. A implantação precisa terminar com execução bem-sucedida antes de registrar.
4. Use **Selecionar arquivo** com uma cópia de teste. **Calcular hash** calcula localmente, sem envio e sem consultar o nó.
5. Clique em **Registrar arquivo** e escolha outro arquivo JSON novo, próprio desse registro. Gere outro bloco pelo mesmo comando do passo 2 e clique em **Acompanhar registro**.
6. Clique em **Verificar arquivo**. A cópia original deve ser encontrada para a conta e contrato exibidos. Uma cópia alterada não registrada deve informar ausência. Isso não é busca global por todas as contas ou redes.
7. Depois de fechar e reabrir a aplicação, use **Abrir implantação**, **Abrir registro** e **Selecionar arquivo** para retomar. Acompanhar e verificar não reenviam a transação original. A porta da janela deve coincidir com a preservada no acompanhamento.

Enquanto uma operação trabalha, a janela continua processando eventos, desabilita as ações de dados e adia o fechamento até a conclusão daquela operação. Não existe promessa de cancelar uma transação enviada. Acompanhar consulta por até três segundos por acionamento; ausência de recibo permite nova consulta do mesmo hash, não novo envio. Não há acompanhamento automático de duração ilimitada.

## Componentes e limites

`Blockchain.RegistryWorkflow` recebe pedidos por valor e compõe os componentes existentes. `TRegistryWorker` executa um pedido sem acessar controles VCL. `Blockchain.RegistryForm` escolhe arquivos, apresenta resultados e recolhe a thread concluída por timer. O formulário é construído em Pascal, sem DFM, pacotes adicionais ou mudanças em projetos abertos no IDE. `demos/Chapter18.Acceptance.dpr` exercita o serviço e o trabalhador contra Anvil real.

Os estados preservados distinguem preparado, enviado, pendente, desconhecido, rejeitado, sucesso e reversão. Um hash apenas calculado usa `hashed`, que não significa transação assinada. A consulta pode informar ausência de um arquivo alterado mesmo quando o acompanhamento original conserva `succeeded`: são perguntas diferentes. Diagnóstico de transporte e prazo esgotado não vira rejeição de negócio nem registro confirmado.

A interface usa exclusivamente chainId 31337, loopback e a chave publicada de byte 46 repetido 32 vezes. Não recebe chaves reais, não implementa cofre, rede pública, tarifas dinâmicas, coordenação entre vários processos escritores ou reorganizações. Cada operação deve ter acompanhamento próprio. Arquivo de acompanhamento não é autenticado contra substituição integral. O caminho selecionado é lido na hora do trabalho; o hash identifica os bytes lidos, sem bloquear alterações externas do arquivo. Não use este laboratório para valores ou documentos sigilosos reais.

O botão **Implantar contrato** é parte do preparo local, não uma implantação em produção. Reiniciar o Anvil vazio exige nova implantação e novos arquivos; abrir um acompanhamento antigo não restaura a rede. Ao terminar, encerre a instância que você abriu.

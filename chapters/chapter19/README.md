# Segurança e confiabilidade no laboratório

Referência: tag `chapter19-examples-2026-10-16`. Delphi 13 Win64 instalado/licenciado, Windows x86-64, Git e PowerShell. Código original Apache-2.0. Nó Anvil e solc permanecem as ferramentas externas fixadas; DPAPI é um serviço nativo do Windows via Crypt32.dll do sistema, sem biblioteca nova a distribuir.

## Executar

Na raiz dos exemplos, com as portas 19545–19547 livres:

```powershell
.\scripts\Test-Chapter19.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0' -Port 19545
```

O roteiro executa 94 testes offline (76 anteriores e 18 novos), três processos positivos e quatro erros operacionais esperados. Depois executa o roteiro completo da aplicação, com 108 regressões e seus cenários de fluxo/janela, e o experimento de perda de recibo. Esses conjuntos se sobrepõem: não somar os totais como casos distintos. `build/Chapter19/full-latest.json` só é gravado após a conclusão dos componentes; aponta para suas pastas de evidência. O ponteiro `latest.json` refere-se somente à parte offline. `-SkipIntegration` serve à investigação offline e não executa Anvil.

## Proteção local

`Blockchain.LocalKeyProtection` chama CryptProtectData/CryptUnprotectData com escopo do usuário atual, sem flag de máquina inteira e sem diálogo. O exemplo só usa a chave privada deliberadamente publicada de byte 46 repetido. Não introduza uma chave real. `SaveNew` exige arquivo novo; `Load` limita o tamanho antes de ler e valida a conta esperada após a recuperação. O cabeçalho DPK1 identifica o formato do exemplo, sem autenticar sua origem.

A demonstração pode ser repetida, sem nó, depois da compilação:

```powershell
$cli = '.\build\Chapter19.Security\Chapter19.Security.exe'
$pasta = 'build\chave de teste ' + [guid]::NewGuid().ToString('N')
& $cli prepare $pasta
& $cli check-key ($pasta + '\published-test-key.dpapi')
& $cli audit ($pasta + '\offline-checkpoint.json')
```

A reabertura ocorre em outro processo sob o mesmo usuário Windows. Não foram exercitados outro usuário, domínio, perfil móvel, restauração de perfil ou recuperação de máquina. A proteção não é cofre, backup nem defesa contra processo comprometido no contexto do usuário. A limpeza de buffers controlados não promete eliminar cópias independentes, dumps ou paginação.

A saída não imprime chave, blob protegido ou diagnóstico arbitrário. O checkpoint da demonstração é uma fixture offline, sem transação enviada. O exportador MinimalTrackingAudit aceita somente schema, estado preservado, chainId, hash da transação e bloco quando presente. Omitir conta/documento/envelope/diagnóstico reduz exposição; o hash da transação continua correlacionável. O resumo não prova a verdade do acompanhamento nem substitui o arquivo de retomada. Arquivos .dpapi ficam ignorados pelo Git e não devem ser distribuídos como dados replicáveis: cada leitor gera os seus.

## Recibo que deixa de estar disponível

`Test-ReceiptLoss.ps1` também pode ser executado separadamente, com os mesmos parâmetros DelphiRoot/Port. O programa nativo implanta, tira uma fotografia do estado do Anvil, registra e observa sucesso. Em seguida usa evm_revert para retornar ao estado anterior ao registro. Trata-se de rollback controlado, não teste do consenso de uma rede pública.

O critério exige documento ausente, recibo ausente apresentado como unknown, observação histórica succeeded preservada, mesmos hash/envelope e nenhum envio adicional. A aplicação VCL e a CLI distinguem estado apresentado de estado armazenado. A CLI wait conserva saída 2 sem recibo e informa storedState. O teste original falhou antes da correção porque o fluxo reapresentava succeeded. Seu critério foi preservado; o histórico não foi apagado para fazer passar.

Isso não implementa prova de ancestralidade do bloco, contagem de confirmações ou finalidade pública. Um recibo ainda disponível não basta para provar que seu bloco pertence ao ramo canônico. A aplicação continua local, com chave conhecida, sem custódia de valores reais, e sua avaliação visual/manual permanece pendente.

# Blockchain na Prática com Delphi

Exemplos e laboratório local do livro de Régys Borges da Silveira, subtítulo *Entenda os conceitos, descubra onde usar e implemente passo a passo*.

O projeto editorial é separado e privado. Este repositório público reúne a preparação técnica reproduzível. Ainda não há cliente blockchain ou contrato implementado.

## Requisitos

- Windows x86-64 e Delphi 13 com compilador Win64, bibliotecas padrão e DUnit. Referência observada: build 37.0.57242.3601. O leitor deve ter uma licença Delphi adequada à sua utilização.
- PowerShell e Git para obter as revisões de fontes.
- Internet para obter os fontes. A preparação e os testes desta etapa não usam conta GitHub, provedor blockchain, carteira ou dinheiro real.

Não são necessários componentes visuais instalados na IDE, OpenSSL externo, Docker, Node.js ou Python. A assinatura e a integração Ethereum ainda serão validadas em etapas futuras. Anvil e solc não são necessários para executar estas suítes.

## Repetir localmente

Clone em uma pasta de sua escolha:

```powershell
git clone https://github.com/regyssilveira/blockchain-na-pratica-com-delphi-exemplos.git
cd blockchain-na-pratica-com-delphi-exemplos
```

Execute em PowerShell. Se a política local bloquear scripts, revise os arquivos e use uma sessão com autorização adequada às regras de sua máquina; o roteiro não altera a política global.

```powershell
.\scripts\Prepare-Dependencies.ps1
.\scripts\Build-UpstreamSuites.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
.\scripts\Run-UpstreamSuites.ps1
```

Adapte somente a raiz Delphi. O script rejeita compiladores de outra geração; não confia em dcc64 encontrado no PATH. Todas as dependências são obtidas nos commits completos de `dependencies.lock.json`; o preparo interrompe se encontrar alterações inesperadas. Ele não sobrescreve checkouts existentes de outra revisão.

Para uma única suíte, acrescente `-Suite SimpleBaseLib4Pascal`, `-Suite HashLib4Pascal`, `-Suite CryptoLib4Pascal` ou `-Suite DUnitX` ao build e à execução. O prazo padrão da execução é de 30 minutos por suíte, ajustável por `-TimeoutMinutes`. Uma expiração é resultado incompleto, nunca aprovação.

Os scripts mantêm fontes em `dependencies/` e compilados/logs em `build/`, ambos ignorados pelo Git. Arquivos da instalação Delphi não são copiados ou publicados. O compilador recebe `--no-config`, caminhos explícitos, `CONSOLE_TESTRUNNER` e `CI`, e produz executáveis Win64. Os logs incluem os argumentos efetivos. As suítes DUnit são executadas a partir da raiz da respectiva biblioteca, pois seus carregadores descobrem os vetores pelo diretório corrente. A suíte DUnitX gera XML e não aguarda Enter.

## Dependências e correção de compatibilidade

CryptoLib4Pascal usa HashLib4Pascal e SimpleBaseLib4Pascal. As suítes dessas bibliotecas usam DUnit incluído no Delphi. A suíte do DUnitX também requer Delphi-Mocks 0.2.2, fixado por commit e utilizado somente nos testes do próprio executor. O submódulo DUnitXML do Delphi-Mocks não é necessário para esse uso e não é obtido.

O preparo aplica uma única correção documentada a `Delphi-Mocks/Source/Delphi.Mocks.pas`: remove `Generics.Defaults` da lista uses da implementação, pois a interface já importa `System.Generics.Defaults`. Essa duplicidade impede a compilação no Delphi 13. O script compara o conteúdo com a revisão original e aceita apenas a transformação especificada; nenhuma regra de teste é alterada.

O preparo também aplica `patches/DUnitX-nunit-duration-locale.patch` ao teste de duração XML do DUnitX. O logger original já usa ponto decimal; a expectativa do teste foi corrigida para o mesmo contrato e ampliada para quatro cenários, com separadores regionais ponto/vírgula e durações 0/1.234 segundos. A configuração é restaurada ao sair do teste. Nenhum teste foi desabilitado e o logger de produção não foi alterado. Detalhes e comprovação de detecção de uma mutação estão em [validação da correção regional](validation/2026-10-16-locale-fix/RESULTADOS.md).

Não habilitar integrações opcionais do DUnitX com ferramentas comerciais de diagnóstico. Os fontes e testes criptográficos permanecem na revisão original. A suíte DUnitX agora passa com 367 testes aprovados e os mesmos 9 ignorados existentes na base. Consultar os resultados observados em `validation/`; não confundir aprovação das suítes com validação da integração blockchain.

Para repetir a verificação de regressão, incluindo uma mutação temporária que deve ser rejeitada:

```powershell
.\scripts\Test-DUnitXLocaleRegression.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

O script restaura o logger em `finally`, recompila e repete a suíte correta. A falha durante a mutação é esperada; o comando só aprova se os quatro casos a detectarem e a execução restaurada passar. Não muda as configurações regionais do Windows nem precisa de conexão com uma rede blockchain.

## Licença

O código original e os scripts deste repositório usam Apache License 2.0, em `LICENSE`. As dependências mantêm suas próprias licenças e avisos, descritos em `THIRD_PARTY_NOTICES.md`. Elas são baixadas de suas origens e não são incorporadas ao histórico deste repositório.

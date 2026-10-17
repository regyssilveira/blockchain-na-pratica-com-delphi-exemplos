# Reprodução local dos fundamentos

Execução em 16/10/2026, Delphi 13 Win64 (37.0.57242.3601), Windows PowerShell 5.1. Clone novo obtido do repositório público, em pasta com espaços. O capítulo 4 começou sem dependências; o capítulo 6 obteve as cinco dependências do manifesto nesse clone. Os demais testes reutilizaram essas dependências conferidas. Não foi usada a pasta de dependências do checkout principal.

| Capítulo | Tag executada | Resultado |
|---|---|---|
| 4 | chapter04-examples-r1-2026-10-16 | Duas linhas esperadas e saída 0 |
| 5 | didactic-chain-accepted-2026-10-16 | 44 testes, quatro hashes e arquivo ausente com saída 1 |
| 6 | chapter06-examples-r1-2026-10-16 | 76 testes, cinco comparações e dois erros operacionais esperados |
| 7 | chapter07-examples-2026-10-16 | 114 testes, 14 condições e três erros operacionais esperados |

Os totais de testes se sobrepõem: não devem ser somados como casos distintos. As quatro saídas de hash Delphi coincidiram com SHA-256 calculado separadamente pelo hashlib da instalação Python do autor. Python não é dependência do programa nem do roteiro do leitor. Os fontes rastreados permaneceram limpos em cada etapa. Não houve alteração das tags, fontes, testes ou dependências para obter os resultados.

Para repetir, clone o repositório, selecione a tag indicada e execute o roteiro do respectivo capítulo a partir da raiz:

```powershell
git fetch origin --tags
git checkout chapter04-examples-r1-2026-10-16
.\scripts\Test-Chapter04.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
git checkout chapter06-examples-r1-2026-10-16
.\scripts\Test-Chapter06.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
git checkout chapter07-examples-2026-10-16
.\scripts\Test-Chapter07.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

Para o capítulo 5, selecione didactic-chain-accepted-2026-10-16, execute Test-Primitives.ps1 sem opções para os 44 testes e com -BuildCli para compilar o console. Use `build/DocumentRegistry.Cli/DocumentRegistry.Cli.exe hash` seguido do caminho de cada arquivo de fixtures/p02. Os manifestos ao lado registram commits e resultados.

Escopo: reprodução automatizada na mesma máquina do autor, em clone independente. Não é avaliação por leitor iniciante ou instalação em outra máquina. Não cobre rede didática, integração Anvil, interface gráfica ou segurança de produção. Exige licença e instalação Delphi adequadas, Git e internet para o preparo inicial. Não houve redistribuição de ferramentas proprietárias.

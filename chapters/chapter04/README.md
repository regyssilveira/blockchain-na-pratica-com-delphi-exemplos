# Capítulo 4 — primeiro programa Delphi

Referência: `chapter04-examples-r1-2026-10-16`. Código original sob Apache License 2.0.

Requer Windows x86-64, Delphi 13 com compilador Win64 instalado/licenciado, Windows PowerShell 5.1 e Git. Nenhuma biblioteca de terceiros, nó de rede ou preparação de dependências é necessária para este exemplo.

Na pasta do repositório:

```powershell
.\scripts\Test-Chapter04.ps1 -DelphiRoot 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
```

O script verifica o compilador da geração 37, compila `demos/Chapter04.Start.dpr` usando apenas a biblioteca padrão e confere saída e código zero. Ajuste a raiz para sua instalação. Resultados em `build/Chapter04.Start`: compile.log, compiler-arguments.txt, output.txt, stderr.txt e acceptance.json.

```text
ambiente_delphi=pronto
bits_do_ponteiro=64
```

Depois da compilação, execute manualmente:

```powershell
.\build\Chapter04.Start\Chapter04.Start.exe
$LASTEXITCODE
```

O resultado esperado do último comando é zero. O programa confere apenas o percurso fonte → compilação → execução Win64; não faz hashes, assinaturas ou comunicação blockchain. O roteiro não valida a licença Delphi nem promete compatibilidade com outra geração.

Se scripts estiverem bloqueados, siga as regras de administração da sua máquina. O roteiro não altera a política global. Não distribua compilador ou bibliotecas comerciais junto com os exemplos.

# Investigação da descoberta da janela — 17/10/2026

Computer Use/@oai/sky retornou as janelas dos controles Calculadora e Notepad++, mas não a aplicação Delphi. Reiniciar a sessão JavaScript não mudou o resultado. A instância original e o processo de execução pertenciam à sessão 1; não foi determinada a sessão interna do helper.

Quatro lançamentos isolados falharam com `launched app did not expose a targetable window`: binário original recompilado em pasta própria; variante com Application.Title explícito; variante com SetCurrentProcessExplicitAppUserModelID; cópia do binário original renomeada RegistryDesktop.exe. Experimentos temporários, sem alteração em fontes versionadas. Instâncias de diagnóstico encerradas, instância manual original preservada. Nenhuma captura ou entrada assistida na janela Delphi.

Causa indeterminada. Os resultados não demonstram defeito do exemplo nem autorizam atribuir a falha a título, nome do executável ou AppUserModelID. Não foi aplicada correção especulativa.

O autor confirmou manualmente os passos 1–7 de chapters/chapter18/README.md: implantação, registro, verificação do original, ausência da cópia alterada e retomada após reabrir. Isso é relato manual, separado do autoteste oculto e sem captura assistida. Responsividade e fechamento durante trabalho ainda precisam de observação visual específica.

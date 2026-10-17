# Resultado técnico do capítulo 19

Roteiro completo aprovado em clone separado com espaços, fontes 4ca9734, dependências e ferramentas preparadas novamente, Windows PowerShell 5.1, Delphi 13 Win64 37.0.57242.3601. Portas 19645–19647; instâncias próprias encerradas.

94 testes offline: 76 anteriores e 18 novos, sem falha/erro/ignorado. Três processos positivos de proteção/recuperação/exportação e quatro erros operacionais esperados. Exercício DPAPI com chave conhecida; nenhum segredo real, arquivo protegido ou bytes recuperados publicados. Não foi exercitado outro usuário ou recuperação de perfil.

Regressão da integração: 108 testes e 13 operações do protótipo; 28 condições da aplicação, autoteste de eventos da janela, três de retomada e quatro com nó parado. Há sobreposição entre as suítes; os totais não são casos exclusivos somáveis. Avaliação visual/manual continua pendente.

Perda de recibo: rollback controlado via evm_snapshot/evm_revert. Antes da correção, a condição absent_receipt_not_presented_as_success falhou: apresentação succeeded apesar de ausência. Critério preservado, correção na apresentação, sem apagar observação histórica. Depois: 11 condições aprovadas, CLI wait saída 2 com state unknown/storedState succeeded; query saída 4, ausência e nonce preservado. Isso não comprova ancestralidade, confirmações ou finalidade pública.

O exportador seleciona campos e não autentica a verdade do arquivo. DPAPI protege dados no contexto do Windows, sem substituir cofre, backup ou proteção de processo comprometido. Cada leitor cria seus próprios arquivos .dpapi ignorados pelo Git; não copiar blobs de outra máquina como fixture portável.

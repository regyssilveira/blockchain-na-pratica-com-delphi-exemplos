# Conferência técnica da revisão do capítulo 6

16/10/2026. Versão chapter06-examples-r1-2026-10-16. Única alteração no fonte criptográfico: corrigir comentário de SignDigest, que pressupunha Keccak-256. O resumo é preparado pelo chamador; o console usa SHA-256 de arquivo. Conferência textual sem comentários/espaçamento confirmou ausência de alteração nas instruções. Primitivas e políticas de verificação preservadas.

Windows PowerShell 5.1, Delphi 13 Win64, 76 testes aprovados (incluindo 44 básicos), zero falhas/erros/ignorados. Cinco casos do console repetidos, mais duas falhas operacionais esperadas com saída 1. O código de saída zero do console indica conclusão do experimento, e não aprovação de todas as comparações. False é esperado em três casos do roteiro.

Entrada idêntica também repetida: original=True, mensagem_alterada=True, outra_chave=False, assinatura_de_outra_mensagem=True e alterada_assinada_novamente=True. As descrições das linhas não são diagnóstico automático dos arquivos do leitor. A verificação isolada não identifica a causa de uma incompatibilidade nem fornece evidência de tempo. A chave de teste é privada no papel algorítmico, mas seu valor está publicado.

As evidências iniciais na pasta superior continuam históricas, vinculadas à tag chapter06-examples-2026-10-16. A revisão usa esta subpasta e mantém a implementação funcional. Não houve integração com rede ou nova avaliação de segurança de produção nesta conferência.

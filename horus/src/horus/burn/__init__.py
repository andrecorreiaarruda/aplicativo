"""Gravador: montagem do conteúdo do disco e envio ao destino.

Corresponde ao BurnerWindowController do Horos, que separa duas etapas:
`prepareCDContent` monta uma pasta com DICOMDIR e extras, e `performBurn`
envia essa pasta ao destino escolhido — CD/DVD, pendrive ou imagem DMG.
"""

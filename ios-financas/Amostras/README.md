# Arquivos de amostra

Servem para testar a importação sem precisar baixar nada do banco.

| Arquivo | Formato | Serve para testar |
|---|---|---|
| `extrato-conta.ofx` | OFX 1.x (SGML) | Extrato de conta corrente, com `FITID`, saldo final e pagamento de fatura |
| `fatura-cartao-nubank.csv` | CSV `date,title,amount` | Fatura de cartão com compras positivas (sinal invertido), parcela e estorno |
| `extrato-conta-itau.csv` | CSV com `;` e vírgula decimal | Extrato no formato brasileiro, com Pix e prefixo de maquininha |

Como usar: mande o arquivo para o iPhone (AirDrop, iCloud Drive ou e-mail),
salve em **Arquivos** e escolha em **Importar extrato** dentro do app.

Importe o mesmo arquivo duas vezes de propósito: na segunda, tudo deve aparecer
como «já existe» e nada deve ser duplicado.

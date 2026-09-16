# Cofre — finanças pessoais para iOS

App de finanças pessoais para uso próprio, escrito em SwiftUI + SwiftData.
Organiza contas e cartões, **lê** as operações a partir dos extratos que você
mesmo exporta do banco, e acompanha metas de gasto, de economia e de
investimento.

Feito para um único usuário, num único aparelho. Não tem cadastro, não tem
servidor, não tem plano pago.

---

## O princípio: o app só lê

Foi a exigência que guiou o desenho. O aplicativo **não possui código capaz de
movimentar dinheiro** — não é uma opção desligada nos ajustes, a capacidade
simplesmente não existe. Não há chamada de pagamento, de transferência nem de
Pix em lugar nenhum.

Na prática:

- não pede senha de banco nem guarda credencial de acesso;
- não envia lançamento nenhum para a internet;
- não tem conta de usuário nem sincronização entre aparelhos;
- os dados ficam num SQLite dentro do contêiner do app, protegido pela
  criptografia do iOS, com trava de Face ID na entrada.

Até o protocolo que qualquer fonte de dados futura precisa cumprir
(`FinanceSyncProvider`) só descreve operações de leitura. Um agregador plugado
ali continua sem conseguir mover dinheiro, porque não existe método para isso.

## De onde vêm os dados

**Hoje — importação de arquivo (funciona com qualquer banco, custo zero):**
você exporta o extrato ou a fatura pelo app do banco e o Cofre lê.

- **OFX / QFX** — formato preferido, traz identificador único por operação.
  Suporta OFX 1.x (SGML, tags sem fechamento) e 2.x (XML), em UTF-8 ou
  ISO-8859-1.
- **CSV / TSV / TXT** — detecção automática de separador (`;`, `,`, tab), de
  decimal (`1.234,56` ou `1,234.56`) e de formato de data, com modelos prontos
  para Nubank (conta e cartão), Inter, Itaú e C6, além do mapeamento manual de
  colunas.
- **Lançamento manual**, para o que não vem em arquivo.

O caminho curto: no app do banco, na hora de exportar, toque em **Compartilhar
e escolha o Cofre**. O app se registra no iOS como leitor de OFX, QFX, CSV e TSV
e aparece sozinho na folha de compartilhamento, sem passar pelo app Arquivos. O
extrato chega e a tela de revisão abre direto — a conferência continua
obrigatória, receber o arquivo mais rápido não pula essa etapa. O endereço
`cofre://importar` abre a tela de importação vazia, para um atalho na tela de
início.

Reimportar o mesmo período não duplica nada: a deduplicação usa o `FITID` do OFX
quando existe e, quando não existe, uma impressão digital de
conta + data + valor + descrição normalizada.

**Depois — sincronização automática (preparada, desligada):** o acesso direto ao
Open Finance do Banco Central é restrito a instituições autorizadas. Para um app
pessoal o caminho é um agregador (Pluggy, Belvo), que exige conta própria e faz
os dados passarem por um terceiro. O encaixe já existe em `Sync/`:
`PluggyProvider` guarda credenciais no Keychain
(`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, sem backup e sem sair do
aparelho) e falha de forma explícita enquanto não for configurado, em vez de
fingir que sincronizou.

## O que o app faz

**Contas** — corrente, poupança, conta de pagamentos, investimento e dinheiro em
espécie. O saldo nunca é armazenado: é sempre o saldo inicial mais a soma dos
lançamentos, então nenhuma importação consegue deixá-lo inconsistente com o
extrato. O patrimônio separa o que está disponível do que está guardado.

**Cartões** — ciclo de fatura de verdade: você informa o dia de fechamento e o
de vencimento, e cada compra cai na fatura certa (compra até o dia do fechamento
entra na fatura que fecha naquele dia; depois disso, vai para a próxima). Mostra
fatura aberta, projeção de onde ela deve fechar no ritmo atual, limite
disponível e o total de parcelas já contratadas para as faturas seguintes.
Mudar o dia de fechamento realoca as compras já importadas.

**Lançamentos** — busca, filtros por mês, tipo, categoria e origem; edição com o
texto original do banco sempre preservado; parcelamento; e a marcação "ignorar
nos totais" para o que não deve entrar no orçamento.

**Categorização automática** — por palavra-chave (mais de 200 estabelecimentos
brasileiros já mapeados: iFood, Enel, Drogasil, Ipiranga, Vivo…) e por regras
aprendidas: quando você corrige a categoria de um lançamento, o app guarda o
padrão do estabelecimento e acerta sozinho na próxima importação.

**Envelopes** — o método clássico, digital. Você separa um valor por categoria
no início do mês e cada gasto tira de lá. O que diferencia de um teto mensal é
que **o saldo atravessa o mês**: gastou R$ 740 do envelope de R$ 900? Outubro
começa com R$ 1.060 dentro dele. Estourou? O buraco vai junto, porque o dinheiro
saiu de algum lugar de verdade.

Cada envelope escolhe o que acontece na virada:

| Política | Sobra | Falta | Para quê |
|---|---|---|---|
| Acumula sobra e falta | atravessa | atravessa | o padrão, e o método de verdade |
| Acumula só a sobra | atravessa | perdoada | evita que um mês ruim contamine os seguintes |
| Zera todo mês | descartada | perdoada | teto mensal comum, para delivery e afins |

Dá para **transferir entre envelopes** — tirar do lazer e pôr no mercado, como
se fazia com as notas de papel — e as duas pontas ficam ligadas, então desfazer
uma desfaz a outra. Reforços e retiradas manuais também ficam registrados.

O número grande de cada linha é o **disponível**, não o gasto: você olha o que
tem, não o quanto falta para estourar. As barras trazem um marcador do ritmo
esperado para o dia de hoje, e a tela mostra quanto da sua renda ainda não tem
envelope nenhum — a pergunta central do método.

**Divisão da renda** — plano 50/30/20 editável (fatias, percentuais e cores),
comparando planejado com realizado. A renda base pode ser digitada ou calculada
pela média das receitas dos últimos meses — o que é mais honesto para renda
variável. Na fatia de investir, superar a meta conta como acerto, não como
estouro.

**Metas de economia e investimento** — quanto juntar, até quando, quanto já foi
aportado e quanto falta guardar por mês. O app avisa quando a soma das metas
pede mais por mês do que o seu plano de alocação reserva.

**Contas fixas** — aluguel, assinaturas, mensalidades. O app confere se cada uma
já apareceu no extrato do mês (nome parecido + valor próximo) e lembra do
vencimento. Só isso: ele nunca paga nada.

**Exportação** — CSV completo com data, descrição original, valor, categoria e
origem. Você continua dono dos seus dados mesmo se parar de usar o app.

## Como rodar

Requer **Xcode 16+** e **iOS 17+** (o app usa SwiftData e Swift Charts).

```bash
open ios-financas/Cofre.xcodeproj
```

1. Selecione o target **Cofre**.
2. Em *Signing & Capabilities*, escolha seu Apple ID em **Team** e troque o
   **Bundle Identifier** `com.exemplo.cofre` por algo seu
   (ex.: `com.seunome.cofre`).
3. Rode no simulador, ou conecte o iPhone e rode nele.

Com uma conta Apple gratuita o app fica instalado por 7 dias e depois precisa
ser reinstalado pelo Xcode. Com o Apple Developer Program (US$ 99/ano) vale 1
ano. Para uso pessoal não é preciso publicar na App Store.

Sem dados ainda? **Ajustes → Carregar dados de exemplo** enche o app com uma
conta, um cartão e cinco meses de lançamentos. Depois, **Apagar tudo e
recomeçar** limpa. Para testar a importação, use os arquivos em
[`Amostras/`](Amostras/).

## Como o código está organizado

```
Config/         Info.plist com os tipos de arquivo que o app abre
Cofre/
  App/          entrada, trava por Face ID, preferências, caixa de entrada de arquivos
                compartilhados, contêiner SwiftData e dados iniciais
  Models/       modelos SwiftData: conta, cartão, lançamento, categoria, orçamento, meta, plano
  Core/         dinheiro em Decimal, datas e MonthKey, ciclo de fatura, normalização de texto,
                tema, o FinanceEngine e o EnvelopeEngine — todo o cálculo em funções puras
  Import/       leitor de OFX, leitor de CSV, categorizador e o serviço de importação
  Sync/         o protocolo só-leitura e os provedores (arquivo, e o agregador desligado)
  Features/     uma pasta por tela: Resumo, Contas, Cartões, Lançamentos, Planejar (envelopes,
                divisão da renda, metas, contas fixas, categorias), Importar, Ajustes
  Shared/       componentes de interface reaproveitados
```

Duas decisões que explicam o resto do código:

**Dinheiro é `Decimal`, nunca `Double`.** Em extrato, o arredondamento binário
do `Double` vira diferença de centavo e, no fim do mês, saldo que não bate.

**O cálculo mora em funções puras.** `FinanceEngine` recebe arrays já carregados
e devolve números; não toca no banco. As telas buscam com `@Query` e passam os
dados. Isso contorna as limitações de predicado do SwiftData e deixa cada número
conferível isoladamente.

**Envelope não se calcula sozinho.** O saldo de setembro depende de agosto, que
depende de julho. Por isso o `EnvelopeEngine` varre os meses desde o início
escolhido numa passada só, acumulando todos os envelopes ao mesmo tempo, em vez
de fazer uma consulta por envelope. O mês inicial é a âncora que impede o
cálculo de voltar no tempo para sempre — e ele é gravado em disco na primeira
abertura, senão cada virada de mês viraria um novo "início" e apagaria o
acúmulo.

## Limites conhecidos

- **Sem multimoeda.** Tudo é BRL. Compra internacional entra pelo valor
  convertido que o banco informa na fatura.
- **Sem cotação de investimento.** O app acompanha o quanto você aportou, não a
  rentabilidade da carteira.
- **Conciliação é sua.** Se o saldo calculado não bater com o do banco, falta ou
  sobra extrato — a tela da conta mostra os dois números lado a lado para você
  achar o buraco.
- **Parcelamento** é reconhecido pela descrição ("3/10", "PARC 03 DE 10"). O que
  o banco não escrever, você marca à mão.
- **Sem backup automático.** Exporte o CSV de vez em quando.

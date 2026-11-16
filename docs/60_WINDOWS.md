# Windows

O aplicativo é o mesmo do Linux: mesmo código, mesma conta, mesmos dados
no Supabase. Este documento cobre o que é próprio do Windows — preparar o
computador, instalar e o que conferir na primeira vez.

> **Situação**: o projeto está preparado (nome, ícone, instalador, uma
> janela só), mas o aplicativo ainda não foi validado em uso no Windows.
> A lista no fim deste documento é o roteiro dessa validação.

## Preparar o computador (uma vez)

1. **Git** — <https://git-scm.com/download/win>, opções padrão.
2. **Visual Studio 2022 Community** (ou só o *Build Tools*), com a carga
   de trabalho **Desenvolvimento para desktop com C++**. É o compilador
   que o Flutter usa; o editor em si não é necessário.
3. **Flutter** — canal estável, 3.44 ou mais novo. Descompacte em uma
   pasta sem espaços (por exemplo `C:\dev\flutter`) e acrescente
   `C:\dev\flutter\bin` ao `Path` do usuário.
4. **Modo de desenvolvedor do Windows** — o Flutter cria links simbólicos
   para os plugins e o Windows só permite isso com esse modo ligado.
   Abra com `start ms-settings:developers` e ative.
5. Confira num terminal novo:

   ```powershell
   flutter doctor
   ```

   As linhas *Flutter*, *Windows Version* e *Visual Studio* precisam
   estar verdes. Android e Chrome não interessam aqui.

## Instalar

```powershell
git clone https://github.com/andrecorreiaarruda/aplicativo.git
cd aplicativo
```

Copie o arquivo `.env` do computador Linux para a raiz do projeto (ele
não vai para o Git). Sem ele, o aplicativo abre só com dados locais, sem
login.

```powershell
.\scripts\install-windows.cmd
```

Compila em modo release, instala em
`%LOCALAPPDATA%\Programs\ORION ServiceLog` e cria o atalho no menu
Iniciar. Não pede administrador. A primeira compilação demora alguns
minutos.

```powershell
.\scripts\install-windows.cmd -Desktop     # também cria atalho na área de trabalho
.\scripts\install-windows.cmd -NoBuild     # reinstala o que já foi compilado
.\scripts\install-windows.cmd -Uninstall   # remove, preservando os dados locais
```

Para atualizar: feche o aplicativo, `git pull` e rode o instalador de
novo.

## Onde ficam os dados

| O quê | Onde |
|---|---|
| Programa | `%LOCALAPPDATA%\Programs\ORION ServiceLog\` |
| Banco local e sessão | `%APPDATA%\ORION\ORION ServiceLog\` |
| PDFs das OS | `Documentos\ORION ServiceLog\Ordens de serviço\` |

- A pasta do banco sai do nome da empresa e do produto gravados em
  `windows\runner\Runner.rc`. **Não mude esses dois nomes** depois da
  primeira instalação: o aplicativo passaria a procurar os dados em outra
  pasta.
- Se a pasta Documentos estiver no OneDrive, os PDFs das OS vão para lá e
  sincronizam com a nuvem da Microsoft.

## O que é por computador

Clientes, equipamentos e atendimentos vêm do Supabase no primeiro login.
Ficam só no computador onde foram criados:

- os **dados do emitente** da OS — preencha de novo, ou deixe as chaves
  `ORION_EMITENTE_*` no `.env` e use "Usar meus dados padrão";
- os **complementos** de cada OS (solicitante, setor, materiais);
- o **registro das OS emitidas** e os próprios PDFs.

Antes de trocar de computador, sincronize: o que está na fila de envio de
um não aparece no outro até subir.

## Uma janela só

Abrir o atalho com o aplicativo já aberto traz a janela existente para a
frente, em vez de abrir outra. Duas janelas gravariam a mesma base local
uma por cima da outra. No Linux é igual.

O mesmo vale para `flutter run -d windows`: com o aplicativo instalado
aberto, a execução de desenvolvimento não abre. Feche o instalado antes.

## Levar para outro computador sem compilar

Copie a pasta `%LOCALAPPDATA%\Programs\ORION ServiceLog` inteira. O outro
computador precisa do *Microsoft Visual C++ Redistributable* (x64), que a
maioria já tem. O `.env` usado na compilação vai embutido no executável —
incluindo os dados do emitente, se estiverem lá.

## Roteiro da primeira validação

- [ ] `install-windows.cmd` compila e termina com "Pronto."
- [ ] O atalho aparece no menu Iniciar com o ícone da ORION.
- [ ] A janela abre com o título "ORION ServiceLog".
- [ ] Um segundo clique no atalho não abre outra janela.
- [ ] Login com a conta de sempre; os atendimentos aparecem.
- [ ] Fechar e abrir de novo: continua logado.
- [ ] Criar um atendimento, sincronizar e conferir no Linux (ou no
      painel do Supabase).
- [ ] Desligar a rede, criar outro, religar: a fila esvazia.
- [ ] Emitir uma OS: o PDF abre no leitor padrão.
- [ ] "Abrir pasta" mostra `Documentos\ORION ServiceLog\Ordens de serviço`.
- [ ] Busca no histórico devolve resultados.
- [ ] Tema claro e escuro.
- [ ] `-Uninstall` remove o programa e mantém a pasta de dados.

## Se der errado

| Sintoma | Causa provável |
|---|---|
| "Building with plugins requires symlink support" | Modo de desenvolvedor desligado. |
| "Unable to find suitable Visual Studio toolchain" | Falta a carga "Desenvolvimento para desktop com C++". |
| O aplicativo abre sem tela de login | Compilado sem `.env`. |
| Acentos trocados nas mensagens do instalador | O `.ps1` perdeu a marca UTF-8 (BOM) ao ser editado. |
| "O ORION ServiceLog está aberto" ao instalar | Feche a janela; se não houver, encerre `servicelog_ai.exe` no Gerenciador de Tarefas. |

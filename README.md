# Cuco

O pássaro que salta do relógio, diz o que tem a dizer e volta para dentro.

Uma app minúscula para a barra de menus do macOS que te lembra de fazer pausas:
descansar os olhos (a regra 20-20-20), levantares-te — e o que mais quiseres,
porque os lembretes são teus e crias os que precisares.

Por omissão é só uma notificação. O ecrã inteiro existe, mas só se o pedires.

## Instalação rápida

Precisas de macOS 13 ou superior, das ferramentas de linha de comandos da Apple
(`xcode-select --install`) e de um certificado **Apple Development** no keychain —
se nunca abriste o Xcode, abre-o uma vez e inicia sessão com o teu Apple ID em
Settings → Accounts, que ele cria um. Sem o certificado a app compila e instala na
mesma, mas fica muda: o macOS não entrega notificações a apps assinadas ad-hoc.

```bash
git clone https://github.com/danielmsrodrigues/cuco.git
cd cuco
./build.sh --install
```

Instala em `~/Applications/Cuco.app`, arranca-a e põe o som do cuco em
`~/Library/Sounds`. À primeira vez o macOS pergunta se pode enviar notificações —
diz que **sim**, senão a app fica muda (e avisa-te disso no menu).

Para compilar sem instalar, corre `./build.sh` e fica em `build/Cuco.app`.

### Sobre a assinatura

O `build.sh` assina com o primeiro certificado **Apple Development** do teu
keychain. Não é vaidade: o macOS recusa notificações a apps assinadas ad-hoc, sem
sequer mostrar o pedido de permissão — o `requestAuthorization` devolve logo um
erro. Sem certificado, o script avisa-te e assina ad-hoc à mesma, para poderes
experimentar o resto.

## O que a app faz

Cada **lembrete** tem nome, mensagem, ícone, de quanto em quanto tempo aparece e
quanto tempo dura a pausa. Vêm dois de origem:

| Lembrete | De quanto em quanto | Dura |
|---|---|---|
| Olhos | 20 min | 20 s |
| Andar | 50 min | 5 min |

A regra 20-20-20 — a cada 20 minutos, 20 segundos a olhar para algo a 20 pés
(≈ 6 metros) — é a recomendação habitual para o cansaço visual de quem passa o
dia ao ecrã.

Podes criar os teus: *Estudo*, *Beber água*, *Postura*, o que fizer sentido.
Menu → Lembretes → Novo lembrete.

**Detalhes que interessam:**

- **Não te chateia quando não estás lá.** Se ficares 5 minutos sem tocar no Mac,
  isso já foi uma pausa e a contagem recomeça sozinha.
- **As pausas não se atropelam.** Uma pausa longa serve também as curtas: quando
  a de andar dispara, a dos olhos volta ao início.
- **Na barra de menus** vês um contador por lembrete ligado, cada um com o seu
  ícone. Durante a pausa vês o tempo que falta, e os outros continuam à vista.
- **Ecrã inteiro (opcional).** Fundo desfocado, anel de progresso, contador,
  botões de adiar e saltar, e Esc. Entra e sai com fade.
- **Aviso antes do ecrã inteiro.** 10 segundos antes chega uma notificação com
  duas saídas: *Agora não, só o aviso* faz aquela pausa passar só por notificação,
  e *Adiar 5 min* empurra-a para a frente.
- **Som.** 13 sons do sistema, "sem som", e um cuco sintetizado à mão
  (`Tools/fazsom.py` — duas notas, a segunda uma terceira menor abaixo). O som
  toca quando o escolhes, para ouvires antes de decidir.
- **Silenciar** 1 hora, 2 horas ou até amanhã.

## Menu

```
Olhos: daqui a 12 min
Andar: daqui a 34 min
───────────────────────
Fazer pausa agora      ▸
Adiar 5 minutos
Recomeçar a contagem
───────────────────────
Lembretes              ▸   ligar/desligar, tempos, nome, mensagem, ícone, apagar, criar
Silenciar              ▸
───────────────────────
☑ Iniciar com o sistema
☐ Pausa em ecrã inteiro
Mais opções            ▸   contagem na barra, som, aviso de fim, aviso prévio
───────────────────────
Sair
```

Os campos de tempo aceitam `45`, `30 s`, `2 min`, `1h` ou `1:30`.

## Testar sem esperar

```bash
swift Tools/testar.swift
```

Dispara já uma pausa do primeiro lembrete ligado.

## Notas

- Com um Foco ou Não Incomodar ligado, o macOS esconde estas notificações como
  esconde as outras. Para as deixar passar, adiciona o Cuco às apps permitidas em
  Definições do Sistema → Foco.
- Se disseres "não permitir" ao pedido de notificações, a app mostra um aviso no
  menu e leva-te às definições. O macOS guarda o "não", por isso tem de ser ligado
  lá — um novo pedido não aparece.

## Desinstalar

```bash
pkill -x Cuco
rm -rf ~/Applications/Cuco.app ~/Library/Sounds/Cuco.aiff
defaults delete net.danielrodrigues.cuco
```

E tira o Cuco de Definições do Sistema → Geral → Itens de início de sessão.

## Estrutura

```
Sources/main.swift      app, menu, agendamento, ecrã de pausa
Sources/Reminder.swift  o modelo de um lembrete
Tools/fazsom.py         sintetiza o "cu-cu"
Tools/makeicon.swift    gera o ícone da app
Tools/testar.swift      dispara uma pausa para testar
build.sh                compila, assina e instala
```

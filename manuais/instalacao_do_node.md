# Instalação do Node.js no cPanel (AlmaLinux 9)

Este manual descreve a instalação oficial do Node.js no **cPanel/WHM** usando **EasyApache 4** em **AlmaLinux 9**.

---

## Pré-requisitos

- Acesso **root** ao servidor
- cPanel/WHM instalado
- Apache 2.4 (EasyApache 4)

---

## Escolha da versão do Node.js

As versões disponíveis seguem o padrão:

- `ea-nodejs22`
- `ea-nodejs20`
- `ea-nodejs18`
- `ea-nodejs16`

No exemplo abaixo será usada a versão **22**.

---

## Instalação via linha de comando

Execute como **root** via SSH ou Terminal do WHM:

```bash
nodepkg=ea-nodejs22

dnf install -y ea-apache24-mod_env ea-apache24-mod-passenger "$nodepkg"
```

> No AlmaLinux 9, utilize **apenas** `ea-apache24-mod-passenger`.

---

## Reiniciar o Apache

```bash
systemctl restart httpd
```

---

## Verificação da instalação

```bash
/opt/cpanel/ea-nodejs22/bin/node -v
/opt/cpanel/ea-nodejs22/bin/npm -v
```

Se os comandos retornarem a versão, a instalação foi concluída com sucesso.

---

## (Opcional) Adicionar Node.js ao PATH global

```bash
ln -sf /opt/cpanel/ea-nodejs22/bin/node /usr/local/bin/node
ln -sf /opt/cpanel/ea-nodejs22/bin/npm  /usr/local/bin/npm
ln -sf /opt/cpanel/ea-nodejs22/bin/npx  /usr/local/bin/npx
```

---

## Uso no cPanel

Após a instalação:

1. Acesse **cPanel do usuário**
2. Vá em **Application Manager** ou **Setup Node.js App**
3. Crie a aplicação Node.js

O Passenger será usado automaticamente para executar a aplicação.

---

## Exemplo de aplicação Node.js

Exemplo mínimo usando **Express** para testar a aplicação no cPanel.

### Estrutura de arquivos

```text
app/
├── app.js
├── package.json
└── passenger_wsgi.js
```

### package.json

```json
{
  "name": "exemplo-node-cpanel",
  "version": "1.0.0",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.19.0"
  }
}
```

### app.js

```js
const express = require('express');
const app = express();

app.get('/', (req, res) => {
  res.send('Node.js rodando no cPanel com AlmaLinux 9');
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Servidor iniciado na porta ${port}`);
});
```

### passenger_wsgi.js

```js
const app = require('./app');
module.exports = app;
```

### Instalar dependências

Execute dentro do diretório da aplicação:

```bash
npm install
```

Após isso, configure o diretório no **Setup Node.js App** do cPanel e inicie a aplicação.

---

## Observações

- O Passenger gerencia o processo Node.js
- Não utilize `pm2` ou `forever` no cPanel
- Logs ficam disponíveis no gerenciador da aplicação

---

## Fim


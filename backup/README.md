<div align="center">
    <a href="https://br.freepik.com/autor/juicy-fish" rel="noopener">
        <img width=auto height=200px src="https://i.imgur.com/E5Yk0Nu.png" alt="Backup Logo">    
    </a>
</div>

# Backup Docker Volumes
Script feito em bash para facilitar o backup diário de [volumes do docker](https://docs.docker.com/engine/storage/volumes/), bem como a restauração do backup caso seja necessário. Dividido em cliente e servidor.

> **ATENÇÃO**: Apenas use esse script em produção se você souber o que está fazendo, não me responsabilizo por eventuais perdas ou danos de qualquer natureza.


## Como Funciona
A estratégia é simples: os volumes apontados numa variável do script são comprimidos e enviados diariamente utilizando [rsync](https://manpages.debian.org/bookworm/rsync/rrsync.1.en.html) e [cronjob](https://www.hostinger.com.br/tutoriais/cron-job-guia). Apenas os backups mais recentes de cada volume são enviados. Do lado do servidor há outro script para gerenciar os arquivos, sendo guardados os diários, semanais e mensais.


## Requisitos
- [Acesso via SSH](https://www.digitalocean.com/community/tutorials/how-to-use-ssh-to-connect-to-a-remote-server-pt) do servidor de backup
- [rsync](https://manpages.debian.org/bookworm/rsync/rrsync.1.en.html) tanto no lado do cliente como do servidor


## Uso
**Dicas**: use a opção ``-n`` para rodar em modo de simulação, ``-h`` para ver os comandos disponíveis.

### Cliente
- Baixe o ``backup-client.sh`` e torne-o executável: ``chmod +x backup-client.sh``
- Altere as variáveis dentro do ``backup-client.sh``:
``BACKUP_DEST_FOLDER``, ``BACKUP_DEST_HOST`` e ``SERVICES`` com os valores necessários.
- Execute ``./backup-client.sh setup`` para criar as pastas necessárias e o cronjob diário

### Servidor
- Baixe o ``backup-server.sh`` e torne-o executável: ``chmod +x backup-server.sh``
- Altere a variável dentro do ``backup-server.sh``: ``DOMAINS`` com os valores necessários.
- Execute ``./backup-server.sh setup`` para criar as pastas necessárias e os cronjobs


## Autor
[@RenanGalvao](https://renangalvao.github.io/whoami/)


## Contribuições
São bem-vindas desde que levem em consideração o escopo que estes scripts buscam atender.

## Detalhes Sobre os Scripts
### backup-client.sh
- Os backups são feitos às 11:59pm.
- Localmente são guardados os backups de até 7 dias.
- Ao restaurar algum backup o container(s) associado ao serviço é/são parado(s) momentaneamente.
- Na mesma rotina de backup é executada a remoção dos backups acima de 7 dias e o envio dos mais recentes para o servidor.

### backup-server.sh
- As rotinas são executadas por volta de 12:00am para evitar race conditions com o cliente.
- Existem 3 rotinas principais: a diária, a semanal e a mensal:
    - A diaria remove os backups com mais de 7 dias da pasta ``daily`` de cada domínio/volume.
    - A semanal além de remover os backups com mais de 30 dias da pasta ``weekly`` de cada domínio/volume, também pega os backups mais recentes da pasta ``daily`` e copia para a pasta ``weekly`` em seus respectivos domínios/volumes.
    - A mensal além de remover os backups com mais de 365 dias da pasta ``monthly`` de cada domínio/volume, também pega os backups mais recentes da pasta ``weekly`` e copia para a pasta ``monthly`` em seus respectivos domínios/volumes.


## TODO
- [ ] Permitir restauração do backup através do servidor (atualmente apenas é possível com os arquivos locais do cliente)
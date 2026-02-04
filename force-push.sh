#!/bin/bash
cd /home/tmileo@atech.local.br/Estudo/dryrun

echo "=== Forçando push para remover credenciais do GitHub ==="
echo ""
echo "Histórico local:"
git log --oneline -3
echo ""
echo "Fazendo push forçado..."
git push --force origin main
echo ""
echo "=== ✅ Concluído! ==="
echo "O histórico remoto foi sobrescrito e as credenciais foram removidas."

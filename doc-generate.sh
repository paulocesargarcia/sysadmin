#!/bin/bash

SCRIPT_FILE="$1"
OUTPUT_FILE="README.md"

# Verifica se o arquivo de script existe
if [ ! -f "$SCRIPT_FILE" ]; then
    echo "Arquivo $SCRIPT_FILE não encontrado."
    exit 1
fi

# Limpa o arquivo de saída
> "$OUTPUT_FILE"

# Cabeçalho do README
echo "# $(basename "$SCRIPT_FILE" .sh) Documentation" >> "$OUTPUT_FILE"
echo >> "$OUTPUT_FILE"

# Flag para identificar quando estamos dentro de um bloco de comentário
inside_comment_block=false

# Percorre o arquivo de script e escreve os blocos de comentários no README.md
while IFS= read -r line; do
    if [[ "$line" =~ ^/\*\* ]]; then
        inside_comment_block=true
        echo "## Descrição" >> "$OUTPUT_FILE"
    elif [[ "$inside_comment_block" == true && "$line" =~ \*/ ]]; then
        inside_comment_block=false
        echo >> "$OUTPUT_FILE" # Adiciona uma linha em branco após cada bloco
    elif [[ "$inside_comment_block" == true ]]; then
        # Formata @param e @example como subtítulos, o restante como texto normal
        if [[ "$line" =~ \@param ]]; then
            echo "### Parâmetro" >> "$OUTPUT_FILE"
            echo "- ${line#*param }" >> "$OUTPUT_FILE"
        elif [[ "$line" =~ \@example ]]; then
            echo "### Exemplo de Uso" >> "$OUTPUT_FILE"
        else
            echo "${line#* }" | sed 's/^\* //' >> "$OUTPUT_FILE"
        fi
    fi
done < "$SCRIPT_FILE"

echo "Documentação gerada em $OUTPUT_FILE"

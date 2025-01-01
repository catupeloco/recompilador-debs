#!/bin/bash

# Compruebo si se han proporcionado uno o más nombres de paquetes
if [ $# -lt 1 ]; then
    echo "Uso: $0 <nombre del paquete1> [<nombre del paquete2> ...]"
    exit 1
fi

# Itero sobre cada nombre de paquete proporcionado
for PACKAGE_NAME in "$@"; do
    
    # Busco el bloque correspondiente al paquete en el archivo de estado
    BLOCK=$(awk -v pkg="$PACKAGE_NAME" '
        BEGIN { RS=""; FS="\n" }
        $1 ~ "Package: " pkg { print; found=1 }
        found && $1 ~ /^Package:/ { exit }
    ' /var/lib/dpkg/status)

    # Compruebo si se encontró el bloque
    if [ -z "$BLOCK" ]; then
        echo "No se encontró información para el paquete: $PACKAGE_NAME"
        continue
    fi

    # Extraigo la versión del bloque
    VERSION=$(echo "$BLOCK" | grep -m 1 '^Version: ' | cut -d ' ' -f 2)

    # Defino el nombre del archivo .deb y el directorio de salida
    OUTPUT_DIR="./${PACKAGE_NAME}.${VERSION}"
    DEB_FILE="${PACKAGE_NAME}.${VERSION}.deb"
    echo --------------- $DEB_FILE

    # Elimino el directorio de salida y el archivo .deb si existen
    rm -rf "$OUTPUT_DIR" "$DEB_FILE" 2>/dev/null

    # Creo el directorio con el formato <nombre del paquete>.<versión>
    mkdir -p "$OUTPUT_DIR/DEBIAN"

    # Guardo la información en un archivo control, eliminando la línea "Status: " y comentadas
    echo "$BLOCK" | grep -vE '^Status: |^#Depends:|^#Pre-Depends:' > "$OUTPUT_DIR/DEBIAN/control"

    # Incluyo archivos relacionados en el directorio DEBIAN, sin el nombre del paquete
    find /var/lib/dpkg/info/ -name "$PACKAGE_NAME.*" ! -name "$PACKAGE_NAME.list" -exec sh -c '
        for file; do
            base=$(basename "$file")
            new_name=$(echo $base | sed 's/${PACKAGE_NAME}\.//g')  # Elimino el prefijo del nombre del paquete
            cp "$file" "'"$OUTPUT_DIR"'/DEBIAN/$new_name"
        done
    ' sh {} +

    # Leo el archivo .list y copio los archivos indicados a la carpeta de salida
    LIST_FILE="/var/lib/dpkg/info/$PACKAGE_NAME.list"
    if [ -f "$LIST_FILE" ]; then
        while read -r line; do
            # Verifica si la línea contiene .git
            if [[ "$line" == *".git"* ]]; then
               continue  # Salta al siguiente ciclo si contiene .git
            fi 
            # Creo el directorio si no existe
            mkdir -p "$OUTPUT_DIR$(dirname "$line")"
            # Copio los archivos listados
            cp --preserve=mode,timestamps "$line" "$OUTPUT_DIR$line" 2>&1 |grep -v "omitting directory" | cut -d \' -f3 
    done < "$LIST_FILE"
    else
        echo "No se encontró el archivo de lista para el paquete: $PACKAGE_NAME"
    fi

    # Genero el paquete .deb
    dpkg -b "$OUTPUT_DIR" "$DEB_FILE" >/dev/null

done

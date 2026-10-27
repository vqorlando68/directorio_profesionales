CREATE OR REPLACE PACKAGE pkgln_directorio_profesionales AS
    /*
    || =========================================================================
    || Paquete: pkgln_directorio_profesionales
    || Propósito: Orquestador Transaccional de Negocio expuesto hacia el Frontend
    ||            y API Gateway para el Directorio de Profesionales y Disponibilidad.
    || Estándar: oracle-plsql-architecture
    || =========================================================================
    */

    -- 1. Consultar directorio paginado de profesionales habilitados con filtros
    PROCEDURE p_consultar_directorio (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 2. Consultar disponibilidad y slots de un profesional (por día o semana)
    PROCEDURE p_consultar_disponibilidad (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 3. Consultar catálogos maestros para los filtros del directorio
    PROCEDURE p_consultar_filtros (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 4. Orquestar la actualización de slots de cita (Marcar/Desmarcar) en el bitmap
    --    Calcula automáticamente duracion_minutos si no se proporciona, a partir de id_profesional, tipo de aseguramiento y modalidad
    PROCEDURE p_actualizar_slots_cita (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 5. Marcar o desmarcar un rango explícito de slots pasando id_usuario, fecha_hora y duracion_minutos
    PROCEDURE p_marcar_desmarcar_slots (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

END pkgln_directorio_profesionales;
/


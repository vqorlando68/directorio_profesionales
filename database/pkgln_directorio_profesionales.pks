CREATE OR REPLACE PACKAGE pkgln_directorio_profesionales AS
    /*
    || =========================================================================
    || Paquete: pkgln_directorio_profesionales
    || Propósito: Orquestador Transaccional de Negocio expuesto hacia el Frontend
    ||            y API Gateway para el Directorio de Profesionales y Disponibilidad.
    || Estándar: oracle-plsql-architecture
    || Responsabilidades:
    ||   - Control atómico de transacciones (p_do_commit y ROLLBACK).
    ||   - Toda la lógica de negocio y reglas de dominio:
    ||       * Festivos y domingos (f_es_festivo, trabaja_festivos).
    ||       * Ausencias programadas (f_existe_ausencia).
    ||       * Duración de cita según aseguramiento y modalidad.
    ||       * Jerarquía de horarios (POR_DIA > PERSONALIZADO > BASE).
    ||       * Motor de slots de 5 minutos y vector de 288 bits.
    ||       * Formateo de intervalos a 12 horas AM/PM.
    ||   - Telemetría integral con uti_manejo_trazas_pkg.
    ||   - Registro de excepciones en tkr_errores con uti_ge_excepciones_pkg.p_grabar_log.
    ||   - CERO RAISE_APPLICATION_ERROR hacia el cliente.
    || =========================================================================
    */

    -- 1. Consultar directorio paginado de profesionales habilitados con filtros
    PROCEDURE p_consultar_directorio (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 2. Consultar disponibilidad y slots de un profesional (por día, semana o rango)
    PROCEDURE p_consultar_disponibilidad (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 3. Consultar catálogos maestros para los filtros del directorio
    PROCEDURE p_consultar_filtros (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 4. Consultar únicamente los intervalos disponibles de un día en formato 12h AM/PM
    -- Retorna: [{"INTERVALO":"08:20 PM"},{"INTERVALO":"08:40 PM"},...]
    PROCEDURE p_consultar_intervalos_dia (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 5. Consultar intervalos disponibles en un rango de fechas con formato dd/mm/yyyy
    -- Retorna: [{"fecha":"27/10/2026","intervalos":[{"INTERVALO":"08:20 PM"},...]},...]
    PROCEDURE p_consultar_intervalos_rango (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 6. Orquestar la actualización de slots de cita (Marcar/Desmarcar) en el bitmap
    PROCEDURE p_actualizar_slots_cita (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 7. Marcar o desmarcar un rango explícito de slots pasando id_usuario, fecha_hora y duracion_minutos
    PROCEDURE p_marcar_desmarcar_slots (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

    -- 8. Consultar detalle del profesional seleccionado
    PROCEDURE p_consultar_detalle_profesional (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    );

END pkgln_directorio_profesionales;
/

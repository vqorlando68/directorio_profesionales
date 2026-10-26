CREATE OR REPLACE PACKAGE BODY pkgca_tkr_tiempos_atencion
AS
    /*
    || =========================================================================
    || CUERPO DEL PAQUETE: pkgca_tkr_tiempos_atencion
    || =========================================================================
    */

    -- 1. Obtener duración de cita en minutos recibiendo JSON
    FUNCTION f_obtener_duracion_cita (
        p_json_entrada IN CLOB
    ) RETURN NUMBER IS
        v_id_usuario            NUMBER;
        v_id_tipo_aseguramiento NUMBER;
        v_modalidad             VARCHAR2(10);
        v_duracion              NUMBER;
    BEGIN
        IF p_json_entrada IS NULL THEN
            RETURN 20;
        END IF;

        -- Extraer atributos del JSON con JSON_VALUE
        v_id_usuario            := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario'));
        v_id_tipo_aseguramiento := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento'));
        v_modalidad             := NVL(UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.modalidad'))), 'V');

        IF v_id_usuario IS NULL OR v_id_tipo_aseguramiento IS NULL THEN
            RETURN 20;
        END IF;

        SELECT CASE 
                   WHEN v_modalidad = 'D' AND ta.duracion_domiciliaria IS NOT NULL 
                   THEN ta.duracion_domiciliaria
                   ELSE NVL(ta.duracion, 20)
               END
          INTO v_duracion
          FROM tkr_tiempos_atencion ta
         WHERE ta.id_usuario = v_id_usuario
           AND ta.id_tipo_aseguramiento = v_id_tipo_aseguramiento
           AND ta.activo = 1
           AND ROWNUM = 1;

        IF v_duracion <= 0 THEN
            RETURN 20;
        END IF;

        RETURN v_duracion;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 20;
        WHEN OTHERS THEN
            RETURN 20;
    END f_obtener_duracion_cita;

    -- 2. Consultar configuraciones activas por profesional recibiendo JSON
    FUNCTION f_consultar_x_profesional (
        p_json_entrada IN CLOB
    ) RETURN SYS_REFCURSOR IS
        v_id_usuario NUMBER;
        v_cursor     SYS_REFCURSOR;
    BEGIN
        IF p_json_entrada IS NULL THEN
            OPEN v_cursor FOR
                SELECT ta.id, ta.id_usuario, ta.id_tipo_aseguramiento, ta.duracion, ta.duracion_domiciliaria, ta.activo
                  FROM tkr_tiempos_atencion ta
                 WHERE 1 = 0;
            RETURN v_cursor;
        END IF;

        v_id_usuario := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario'));

        OPEN v_cursor FOR
            SELECT ta.id,
                   ta.id_usuario,
                   ta.id_tipo_aseguramiento,
                   ta.duracion,
                   ta.duracion_domiciliaria,
                   ta.activo
              FROM tkr_tiempos_atencion ta
             WHERE ta.id_usuario = v_id_usuario
               AND ta.activo = 1
             ORDER BY ta.id_tipo_aseguramiento ASC;

        RETURN v_cursor;
    END f_consultar_x_profesional;

END pkgca_tkr_tiempos_atencion;
/

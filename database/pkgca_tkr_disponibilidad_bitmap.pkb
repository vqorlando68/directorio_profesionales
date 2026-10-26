CREATE OR REPLACE PACKAGE BODY pkgca_tkr_disponibilidad_bitmap
AS
    /*
    || =========================================================================
    || CUERPO DEL PAQUETE: pkgca_tkr_disponibilidad_bitmap
    || =========================================================================
    */

    -- 1. Actualizar el vector bitmap_ocupado en tkr_disponibilidad_bitmap (DML Mono-Tabla)
    PROCEDURE p_actualizar_bitmap_ocupado (
        p_json_entrada    IN  CLOB,
        p_filas_afectadas OUT NUMBER
    ) IS
        v_id_usuario            NUMBER;
        v_fecha_str             VARCHAR2(20);
        v_fecha_dia             DATE;
        v_idx_inicio            NUMBER;
        v_idx_fin               NUMBER;
        v_caracter_bit          VARCHAR2(2);
        v_id_convenio           NUMBER;
        v_id_tipo_aseguramiento NUMBER;
        v_modalidad             VARCHAR2(5);
        v_actualizados          NUMBER := 0;

        CURSOR c_bitmaps IS
            SELECT b.ROWID AS fila_id,
                   b.bitmap_ocupado
              FROM tkr_disponibilidad_bitmap b
             WHERE b.id_usuario = v_id_usuario
               AND TRUNC(b.fecha) = TRUNC(v_fecha_dia)
               AND (v_id_convenio IS NULL OR b.id_convenio = v_id_convenio OR b.id_convenio IS NULL)
               AND (v_id_tipo_aseguramiento IS NULL OR b.id_tipo_aseguramiento = v_id_tipo_aseguramiento)
               AND (v_modalidad IS NULL OR b.modalidad = v_modalidad)
             FOR UPDATE OF b.bitmap_ocupado;
    BEGIN
        p_filas_afectadas := 0;

        IF p_json_entrada IS NULL THEN
            RETURN;
        END IF;

        -- Extraer atributos del JSON con JSON_VALUE
        v_id_usuario            := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario'));
        v_fecha_str             := TRIM(JSON_VALUE(p_json_entrada, '$.fecha'));
        v_idx_inicio            := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.idx_inicio'));
        v_idx_fin               := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.idx_fin'));
        v_caracter_bit          := TRIM(NVL(JSON_VALUE(p_json_entrada, '$.caracter_bit'), '1'));
        v_id_convenio           := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio'));
        v_id_tipo_aseguramiento := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento'));
        v_modalidad             := UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.modalidad')));

        IF v_id_usuario IS NULL OR v_fecha_str IS NULL OR v_idx_inicio IS NULL OR v_idx_fin IS NULL THEN
            RETURN;
        END IF;

        v_fecha_dia := TO_DATE(v_fecha_str, 'YYYY-MM-DD');

        IF v_idx_inicio < 1 THEN v_idx_inicio := 1; END IF;
        IF v_idx_fin > 288 THEN v_idx_fin := 288; END IF;
        IF v_caracter_bit NOT IN ('0', '1') THEN v_caracter_bit := '1'; END IF;

        FOR r_b IN c_bitmaps LOOP
            DECLARE
                v_bm_ocupado VARCHAR2(288) := NVL(r_b.bitmap_ocupado, RPAD('0', 288, '0'));
            BEGIN
                IF LENGTH(v_bm_ocupado) < 288 THEN
                    v_bm_ocupado := RPAD(v_bm_ocupado, 288, '0');
                END IF;

                FOR i IN v_idx_inicio..v_idx_fin LOOP
                    v_bm_ocupado := SUBSTR(v_bm_ocupado, 1, i - 1) || v_caracter_bit || SUBSTR(v_bm_ocupado, i + 1);
                END LOOP;

                UPDATE tkr_disponibilidad_bitmap
                   SET bitmap_ocupado      = v_bm_ocupado,
                       fecha_actualizacion = SYSTIMESTAMP AT TIME ZONE 'America/Bogota'
                 WHERE ROWID = r_b.fila_id;

                v_actualizados := v_actualizados + 1;
            END;
        END LOOP;

        p_filas_afectadas := v_actualizados;
    END p_actualizar_bitmap_ocupado;

    -- 2. Consultar vector por profesional y fecha recibiendo JSON
    FUNCTION f_consultar_x_fecha (
        p_json_entrada IN CLOB
    ) RETURN SYS_REFCURSOR IS
        v_id_usuario NUMBER;
        v_fecha_str  VARCHAR2(20);
        v_cursor     SYS_REFCURSOR;
    BEGIN
        IF p_json_entrada IS NULL THEN
            OPEN v_cursor FOR
                SELECT * FROM tkr_disponibilidad_bitmap WHERE 1 = 0;
            RETURN v_cursor;
        END IF;

        v_id_usuario := TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario'));
        v_fecha_str  := TRIM(JSON_VALUE(p_json_entrada, '$.fecha'));

        OPEN v_cursor FOR
            SELECT b.id,
                   b.id_usuario,
                   b.fecha,
                   b.id_convenio,
                   b.id_tipo_aseguramiento,
                   b.modalidad,
                   b.bitmap_disponible,
                   b.bitmap_ocupado,
                   b.slots_disponibles,
                   b.fecha_actualizacion
              FROM tkr_disponibilidad_bitmap b
             WHERE b.id_usuario = v_id_usuario
               AND TRUNC(b.fecha) = TO_DATE(v_fecha_str, 'YYYY-MM-DD')
             ORDER BY b.id_tipo_aseguramiento ASC, b.modalidad ASC;

        RETURN v_cursor;
    END f_consultar_x_fecha;

END pkgca_tkr_disponibilidad_bitmap;
/

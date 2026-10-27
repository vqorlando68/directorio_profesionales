CREATE OR REPLACE PACKAGE BODY pkgcn_directorio_profesionales AS
    /*
    || =========================================================================
    || Paquete: pkgcn_directorio_profesionales (Body)
    || Propósito: Implementación de consultas relacionales multi-tabla y DML
    ||            para el directorio de profesionales y turnos de atención.
    || Estándar: oracle-plsql-architecture
    || Reglas:
    ||   - Cero lógica de negocio (toda decisión funcional reside en pkgln_).
    ||   - Cero control transaccional (p_do_commit y ROLLBACK en pkgln_).
    ||   - Sintaxis tradicional Oracle con uniones (+) obligatorias.
    || =========================================================================
    */

    -- 1. Consultar directorio paginado de profesionales habilitados con filtros multi-tabla
    PROCEDURE p_consultar_profesionales_json (
        p_id_especialidad       IN  NUMBER   DEFAULT NULL,
        p_id_convenio           IN  NUMBER   DEFAULT NULL,
        p_id_tipo_aseguramiento IN  NUMBER   DEFAULT NULL,
        p_modalidad             IN  VARCHAR2 DEFAULT NULL,
        p_busqueda              IN  VARCHAR2 DEFAULT NULL,
        p_pagina                IN  NUMBER   DEFAULT 1,
        p_registros_por_pagina  IN  NUMBER   DEFAULT 12,
        p_json_salida           OUT CLOB
    ) IS
        v_limite          NUMBER := NVL(p_registros_por_pagina, 12);
        v_pagina          NUMBER := GREATEST(NVL(p_pagina, 1), 1);
        v_offset          NUMBER;
        v_total_registros NUMBER := 0;
        v_total_paginas   NUMBER := 0;
        v_json_arr        CLOB;
    BEGIN
        IF v_limite <= 0 THEN
            v_limite := 12;
        END IF;
        v_offset := (v_pagina - 1) * v_limite;

        -- Conteo total de registros relacional multi-tabla
        SELECT COUNT(1)
          INTO v_total_registros
          FROM tkr_usuarios u
         WHERE u.id_estado_usuario = 1
           AND (
               u.id_rol = 4 
               OR EXISTS (SELECT 1 FROM tkr_roles_usuario ru WHERE ru.id_usuario = u.id AND ru.id_rol = 4)
           )
           AND EXISTS (
               SELECT 1 
                 FROM tkr_horarios_profesional h 
                WHERE h.id_usuario = u.id 
                  AND h.activo = 1
           )
           AND (
               p_id_especialidad IS NULL 
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_especialidades_usuario ue 
                    WHERE ue.id_usuario = u.id 
                      AND ue.id_especialidad = p_id_especialidad
               )
           )
           AND (
               p_id_convenio IS NULL
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_horarios_profesional h
                    WHERE h.id_usuario = u.id
                      AND h.activo = 1
                      AND (h.id_convenio = p_id_convenio OR h.id_convenio IS NULL)
               )
           )
           AND (
               p_id_tipo_aseguramiento IS NULL
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_horarios_profesional h
                    WHERE h.id_usuario = u.id
                      AND h.activo = 1
                      AND (h.id_tipo_aseguramiento = p_id_tipo_aseguramiento OR h.id_tipo_aseguramiento IS NULL)
               )
           )
           AND (
               p_modalidad IS NULL
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_franjas_profesional f
                    WHERE f.id_usuario = u.id
                      AND f.activo = 1
                      AND (f.modalidad = UPPER(TRIM(p_modalidad)) OR f.modalidad IS NULL)
               )
           )
           AND (
               p_busqueda IS NULL
               OR UPPER(u.nombres || ' ' || u.apellidos) LIKE '%' || UPPER(TRIM(p_busqueda)) || '%'
               OR UPPER(u.correo_electronico) LIKE '%' || UPPER(TRIM(p_busqueda)) || '%'
           );

        v_total_paginas := CEIL(v_total_registros / v_limite);

        -- Consulta paginada con extracción relacional JSON de profesionales
        SELECT COALESCE(
                   JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'id_usuario'       VALUE prof.id,
                           'nombre_completo'  VALUE TRIM(prof.nombres || ' ' || prof.apellidos),
                           'nombres'          VALUE prof.nombres,
                           'apellidos'        VALUE prof.apellidos,
                           'correo'           VALUE prof.correo_electronico,
                           'telefono'         VALUE prof.telefono,
                           'trabaja_festivos' VALUE NVL(prof.trabaja_festivos, 'N'),
                           'url_foto'         VALUE pkgcn_profesionales.f_url_foto_profesional(prof.id),
                           'especialidades'   VALUE (
                               SELECT JSON_ARRAYAGG(
                                          JSON_OBJECT(
                                              'id'     VALUE e.id,
                                              'nombre' VALUE e.nombre_especialidad
                                          )
                                          RETURNING CLOB
                                      )
                                 FROM tkr_especialidades_usuario ue,
                                      tkr_especialidades        e
                                WHERE ue.id_usuario = prof.id
                                  AND e.id          = ue.id_especialidad
                           ),
                           'modalidades'      VALUE (
                               SELECT JSON_ARRAYAGG(m.modalidad RETURNING CLOB)
                                  FROM (
                                      SELECT DISTINCT f.id_usuario, NVL(f.modalidad, 'TODAS') AS modalidad
                                        FROM tkr_franjas_profesional f
                                       WHERE f.activo = 1
                                  ) m
                                 WHERE m.id_usuario = prof.id
                           )
                       )
                       RETURNING CLOB
                   ),
                   TO_CLOB('[]')
               )
          INTO v_json_arr
          FROM (
              SELECT u.id,
                     u.nombres,
                     u.apellidos,
                     u.correo_electronico,
                     u.telefono,
                     u.trabaja_festivos
                FROM tkr_usuarios u
               WHERE u.id_estado_usuario = 1
                 AND (
                     u.id_rol = 4 
                     OR EXISTS (SELECT 1 FROM tkr_roles_usuario ru WHERE ru.id_usuario = u.id AND ru.id_rol = 4)
                 )
                 AND EXISTS (
                     SELECT 1 
                       FROM tkr_horarios_profesional h 
                      WHERE h.id_usuario = u.id 
                        AND h.activo = 1
                 )
                 AND (
                     p_id_especialidad IS NULL 
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_especialidades_usuario ue 
                          WHERE ue.id_usuario = u.id 
                            AND ue.id_especialidad = p_id_especialidad
                     )
                 )
                 AND (
                     p_id_convenio IS NULL
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_horarios_profesional h
                          WHERE h.id_usuario = u.id
                            AND h.activo = 1
                            AND (h.id_convenio = p_id_convenio OR h.id_convenio IS NULL)
                     )
                 )
                 AND (
                     p_id_tipo_aseguramiento IS NULL
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_horarios_profesional h
                          WHERE h.id_usuario = u.id
                            AND h.activo = 1
                            AND (h.id_tipo_aseguramiento = p_id_tipo_aseguramiento OR h.id_tipo_aseguramiento IS NULL)
                     )
                 )
                 AND (
                     p_modalidad IS NULL
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_franjas_profesional f
                          WHERE f.id_usuario = u.id
                            AND f.activo = 1
                            AND (f.modalidad = UPPER(TRIM(p_modalidad)) OR f.modalidad IS NULL)
                     )
                 )
                 AND (
                     p_busqueda IS NULL
                     OR UPPER(u.nombres || ' ' || u.apellidos) LIKE '%' || UPPER(TRIM(p_busqueda)) || '%'
                     OR UPPER(u.correo_electronico) LIKE '%' || UPPER(TRIM(p_busqueda)) || '%'
                 )
               ORDER BY u.nombres ASC, u.apellidos ASC
              OFFSET v_offset ROWS
               FETCH NEXT v_limite ROWS ONLY
          ) prof;

        SELECT JSON_OBJECT(
                   'codigo'           VALUE 0,
                   'mensaje'          VALUE 'Directorio consultado exitosamente',
                   'total_registros'  VALUE v_total_registros,
                   'total_paginas'    VALUE v_total_paginas,
                   'pagina_actual'    VALUE v_pagina,
                   'registros_pagina' VALUE v_limite,
                   'profesionales'    VALUE JSON_QUERY(v_json_arr, '$' RETURNING CLOB)
                   RETURNING CLOB
               )
          INTO p_json_salida
          FROM DUAL;
    END p_consultar_profesionales_json;

    -- 2. Consultar turnos multi-tabla de un profesional para un día de la semana
    FUNCTION f_consultar_turnos (
        p_id_usuario            IN  NUMBER,
        p_dia_semana            IN  VARCHAR2,
        p_id_convenio           IN  NUMBER   DEFAULT NULL,
        p_id_tipo_aseguramiento IN  NUMBER   DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT h.id,
                   h.hora_desde,
                   h.hora_hasta,
                   h.id_convenio,
                   h.id_tipo_aseguramiento,
                   h.fecha_inicial,
                   h.fecha_final
              FROM tkr_horarios_profesional h
             WHERE h.id_usuario = p_id_usuario
               AND h.dia_semana = p_dia_semana
               AND h.activo = 1
               AND (
                   p_id_convenio IS NULL 
                   OR h.id_convenio = p_id_convenio 
                   OR h.id_convenio IS NULL
               )
               AND (
                   p_id_tipo_aseguramiento IS NULL
                   OR h.id_tipo_aseguramiento = p_id_tipo_aseguramiento 
                   OR h.id_tipo_aseguramiento IS NULL
               )
             ORDER BY CASE WHEN h.id_convenio = p_id_convenio THEN 1 ELSE 2 END,
                      h.hora_desde ASC;

        RETURN v_cursor;
    END f_consultar_turnos;

    -- 3. Consultar catálogos para filtros del directorio (especialidades, convenios, aseguramientos)
    PROCEDURE p_consultar_filtros_catalogo_json (
        p_json_salida OUT CLOB
    ) IS
        v_json_especialidades CLOB;
        v_json_convenios      CLOB;
        v_json_aseguramientos CLOB;
    BEGIN
        -- Especialidades activas
        SELECT COALESCE(
                   JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'id'     VALUE e.id,
                           'nombre' VALUE e.nombre_especialidad
                       )
                       ORDER BY e.nombre_especialidad ASC
                       RETURNING CLOB
                   ),
                   TO_CLOB('[]')
               )
          INTO v_json_especialidades
          FROM tkr_especialidades e;

        -- Convenios activos
        SELECT COALESCE(
                   JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'id'     VALUE c.id,
                           'nombre' VALUE c.nombre_convenio
                       )
                       ORDER BY c.nombre_convenio ASC
                       RETURNING CLOB
                   ),
                   TO_CLOB('[]')
               )
          INTO v_json_convenios
          FROM tkr_convenios c
         WHERE c.estado = 'A';

        -- Tipos de aseguramiento
        SELECT COALESCE(
                   JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'id'     VALUE t.id,
                           'nombre' VALUE t.tipo_aseguramiento
                       )
                       ORDER BY t.id ASC
                       RETURNING CLOB
                   ),
                   TO_CLOB('[]')
               )
          INTO v_json_aseguramientos
          FROM tkr_tipos_aseguramiento t;

        SELECT JSON_OBJECT(
                   'codigo'              VALUE 0,
                   'mensaje'             VALUE 'Catálogos consultados exitosamente',
                   'especialidades'      VALUE JSON_QUERY(v_json_especialidades, '$' RETURNING CLOB),
                   'convenios'           VALUE JSON_QUERY(v_json_convenios, '$' RETURNING CLOB),
                   'tipos_aseguramiento' VALUE JSON_QUERY(v_json_aseguramientos, '$' RETURNING CLOB),
                   'modalidades'         VALUE JSON_ARRAY(
                                                   JSON_OBJECT('codigo' VALUE 'V', 'nombre' VALUE 'Virtual'),
                                                   JSON_OBJECT('codigo' VALUE 'D', 'nombre' VALUE 'Domiciliaria')
                                               )
                   RETURNING CLOB
               )
          INTO p_json_salida
          FROM DUAL;
    END p_consultar_filtros_catalogo_json;

END pkgcn_directorio_profesionales;
/

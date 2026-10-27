CREATE OR REPLACE PACKAGE BODY pkgcn_directorio_profesionales AS
    /*
    || =========================================================================
    || Paquete: pkgcn_directorio_profesionales (Body)
    || Propósito: Implementación de consultas relacionales multi-tabla y DML
    ||            para el directorio de profesionales y turnos de atención.
    || Estándar: oracle-plsql-architecture
    || Reglas:
    ||   - Recibe siempre un payload JSON (p_json_entrada) y evalúa los filtros
    ||     en las sentencias DML/SQL directamente mediante JSON_VALUE.
    ||   - Cero lógica de negocio (toda decisión funcional reside en pkgln_).
    ||   - Cero control transaccional (p_do_commit y ROLLBACK en pkgln_).
    ||   - Sintaxis tradicional Oracle con uniones (+) obligatorias.
    || =========================================================================
    */

    -- Función auxiliar para obtener los días de la semana con horario activo en un rango de fechas
    FUNCTION f_dias_servicio_profesional (
        p_id_usuario   IN NUMBER,
        p_fecha_inicio IN VARCHAR2 DEFAULT NULL,
        p_fecha_fin    IN VARCHAR2 DEFAULT NULL,
        p_id_convenio  IN NUMBER DEFAULT NULL,
        p_id_aseg      IN NUMBER DEFAULT NULL
    ) RETURN VARCHAR2 IS
        v_dias  VARCHAR2(200);
        v_f_ini DATE;
        v_f_fin DATE;
    BEGIN
        IF p_fecha_inicio IS NOT NULL THEN
            IF INSTR(p_fecha_inicio, '/') > 0 THEN
                v_f_ini := TRUNC(TO_DATE(SUBSTR(p_fecha_inicio, 1, 10), 'DD/MM/YYYY'));
            ELSE
                v_f_ini := TRUNC(TO_DATE(SUBSTR(p_fecha_inicio, 1, 10), 'YYYY-MM-DD'));
            END IF;
        ELSE
            v_f_ini := TRUNC(SYSDATE);
        END IF;

        IF p_fecha_fin IS NOT NULL THEN
            IF INSTR(p_fecha_fin, '/') > 0 THEN
                v_f_fin := TRUNC(TO_DATE(SUBSTR(p_fecha_fin, 1, 10), 'DD/MM/YYYY'));
            ELSE
                v_f_fin := TRUNC(TO_DATE(SUBSTR(p_fecha_fin, 1, 10), 'YYYY-MM-DD'));
            END IF;
        ELSE
            v_f_fin := v_f_ini + 6;
        END IF;

        IF v_f_fin < v_f_ini THEN
            v_f_fin := v_f_ini;
        END IF;

        SELECT LISTAGG(d.dia_semana, ', ') WITHIN GROUP (
                   ORDER BY CASE d.dia_semana 
                              WHEN 'LU' THEN 1 
                              WHEN 'MA' THEN 2 
                              WHEN 'MI' THEN 3 
                              WHEN 'JU' THEN 4 
                              WHEN 'VI' THEN 5 
                              WHEN 'SA' THEN 6 
                              WHEN 'DO' THEN 7 
                              ELSE 8 
                            END
               )
          INTO v_dias
          FROM (
              SELECT DISTINCT h.dia_semana
                FROM tkr_horarios_profesional h
               WHERE h.id_usuario = p_id_usuario
                 AND h.activo = 1
                 AND (p_id_convenio IS NULL OR h.id_convenio = p_id_convenio OR h.id_convenio IS NULL)
                 AND (p_id_aseg IS NULL OR h.id_tipo_aseguramiento = p_id_aseg OR h.id_tipo_aseguramiento IS NULL)
                 AND TRUNC(NVL(h.fecha_inicial, v_f_ini)) <= v_f_fin
                 AND TRUNC(NVL(h.fecha_final, v_f_fin)) >= v_f_ini
                 AND (
                     v_f_fin - v_f_ini >= 6
                     OR EXISTS (
                         SELECT 1
                           FROM (
                               SELECT v_f_ini + LEVEL - 1 AS cal_dia
                                 FROM DUAL
                              CONNECT BY LEVEL <= LEAST(v_f_fin - v_f_ini + 1, 366)
                           ) c
                          WHERE CASE UPPER(SUBSTR(TRIM(TO_CHAR(c.cal_dia, 'DY', 'NLS_DATE_LANGUAGE=SPANISH')), 1, 2))
                                  WHEN 'LU' THEN 'LU'
                                  WHEN 'MA' THEN 'MA'
                                  WHEN 'MI' THEN 'MI'
                                  WHEN 'JU' THEN 'JU'
                                  WHEN 'VI' THEN 'VI'
                                  WHEN 'SÁ' THEN 'SA'
                                  WHEN 'SA' THEN 'SA'
                                  WHEN 'DO' THEN 'DO'
                                  ELSE 'LU'
                                END = h.dia_semana
                            AND TRUNC(NVL(h.fecha_inicial, c.cal_dia)) <= c.cal_dia
                            AND TRUNC(NVL(h.fecha_final, c.cal_dia)) >= c.cal_dia
                     )
                 )
          ) d;

        RETURN v_dias;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN NULL;
    END f_dias_servicio_profesional;

    -- 1. Consultar directorio paginado de profesionales habilitados con filtros multi-tabla
    PROCEDURE p_consultar_profesionales_json (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
        v_limite          NUMBER;
        v_pagina          NUMBER;
        v_offset          NUMBER;
        v_total_registros NUMBER := 0;
        v_total_paginas   NUMBER := 0;
        v_json_arr        CLOB;
    BEGIN
        v_limite := NVL(TO_NUMBER(JSON_VALUE(p_json_entrada, '$.registros_pagina')), NVL(TO_NUMBER(JSON_VALUE(p_json_entrada, '$.registros_por_pagina')), 12));
        IF v_limite <= 0 THEN
            v_limite := 12;
        END IF;

        v_pagina := GREATEST(NVL(TO_NUMBER(JSON_VALUE(p_json_entrada, '$.pagina')), 1), 1);
        v_offset := (v_pagina - 1) * v_limite;

        -- Conteo total de registros relacional multi-tabla evaluado con JSON_VALUE
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
               JSON_VALUE(p_json_entrada, '$.id_especialidad') IS NULL 
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_especialidades_usuario ue 
                    WHERE ue.id_usuario = u.id 
                      AND ue.id_especialidad = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_especialidad'))
               )
           )
           AND (
               JSON_VALUE(p_json_entrada, '$.id_convenio') IS NULL
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_horarios_profesional h
                    WHERE h.id_usuario = u.id
                      AND h.activo = 1
                      AND (h.id_convenio = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio')) OR h.id_convenio IS NULL)
               )
           )
           AND (
               JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento') IS NULL
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_horarios_profesional h
                    WHERE h.id_usuario = u.id
                      AND h.activo = 1
                      AND (h.id_tipo_aseguramiento = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento')) OR h.id_tipo_aseguramiento IS NULL)
               )
           )
           AND (
               JSON_VALUE(p_json_entrada, '$.modalidad') IS NULL
               OR EXISTS (
                   SELECT 1 
                     FROM tkr_franjas_profesional f
                    WHERE f.id_usuario = u.id
                      AND f.activo = 1
                      AND (f.modalidad = UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.modalidad'))) OR f.modalidad IS NULL)
               )
           )
           AND (
               JSON_VALUE(p_json_entrada, '$.busqueda') IS NULL
               OR UPPER(u.nombres || ' ' || u.apellidos) LIKE '%' || UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.busqueda'))) || '%'
               OR UPPER(u.correo_electronico) LIKE '%' || UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.busqueda'))) || '%'
           );

        v_total_paginas := CEIL(v_total_registros / v_limite);

        -- Consulta paginada con extracción relacional JSON de profesionales
        -- con la misma estructura oficial de p_consultar_detalle_profesional
        SELECT COALESCE(
                   JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'id'               VALUE prof.id,
                           'id_usuario'       VALUE prof.id,
                           'fullName'         VALUE TRIM(prof.nombres || ' ' || prof.apellidos),
                           'nombre_completo'  VALUE TRIM(prof.nombres || ' ' || prof.apellidos),
                           'trabaja_festivos' VALUE NVL(prof.trabaja_festivos, 'N'),
                           'slug'             VALUE prof.usuario,
                           'gender'           VALUE DECODE(prof.id_genero, 1, 'Masculino', 2, 'Femenino', 3, 'Otro', NULL),
                           'rate'             VALUE (
                               SELECT LEAST(ROUND(AVG(ep.satisfacion_medico), 1), 5) 
                                 FROM tkr_encuesta_paciente ep,
                                      tkr_citas             ct,
                                      tkr_cita_usuarios     cu
                                WHERE ep.id_cita            = ct.id
                                  AND ct.id                 = cu.id_cita
                                  AND cu.id_usuario_atiende = prof.id
                                GROUP BY cu.id_usuario_atiende
                           ),
                           'reviews'          VALUE NVL((
                               SELECT COUNT(1) 
                                 FROM tkr_encuesta_paciente ep,
                                      tkr_citas             ct,
                                      tkr_cita_usuarios     cu
                                WHERE ep.id_cita            = ct.id
                                  AND ct.id                 = cu.id_cita
                                  AND cu.id_usuario_atiende = prof.id
                                GROUP BY cu.id_usuario_atiende
                           ), 0),
                           'specialty'        VALUE (
                               SELECT COALESCE(
                                          JSON_ARRAYAGG(
                                              JSON_OBJECT(
                                                  'id'                  VALUE e.id,
                                                  'nombre_especialidad' VALUE e.nombre_especialidad,
                                                  'tipo_especialidad'   VALUE e.tipo_especialidad
                                              )
                                              RETURNING CLOB
                                          ),
                                          TO_CLOB('[]')
                                      )
                                 FROM tkr_especialidades_usuario eu,
                                      tkr_especialidades         e
                                WHERE eu.id_usuario      = prof.id
                                  AND e.id               = eu.id_especialidad
                           ),
                           'esp_subesp'       VALUE f_nombre_subespecialidades_usuario(prof.id),
                           'subspecialty'     VALUE (
                               SELECT sue.subespecialidad
                                 FROM tkr_especialidades_usuario eud,
                                      tkr_subespecialidad_usu    sue
                                WHERE eud.id_usuario             = prof.id
                                  AND sue.id_especialidad_usuario = eud.id
                                  AND ROWNUM                     = 1
                           ),
                            'days_of_service'  VALUE f_dias_servicio_profesional(
                                                     prof.id,
                                                     COALESCE(JSON_VALUE(p_json_entrada, '$.fecha_inicio'),
                                                              JSON_VALUE(p_json_entrada, '$.fecha_desde'),
                                                              JSON_VALUE(p_json_entrada, '$.fecha_inicial'),
                                                              JSON_VALUE(p_json_entrada, '$.fecha')),
                                                     COALESCE(JSON_VALUE(p_json_entrada, '$.fecha_fin'),
                                                              JSON_VALUE(p_json_entrada, '$.fecha_hasta'),
                                                              JSON_VALUE(p_json_entrada, '$.fecha_final')),
                                                     TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio')),
                                                     TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento'))
                                                 ),
                           'img_url'          VALUE CASE
                                                      WHEN f_archivo_foto(prof.id) IS NULL THEN
                                                          pkgca_tkr_parametros.f_consulta_valor(-7) || 'logo_circulo.png'
                                                      ELSE
                                                          pkgca_tkr_parametros.f_consulta_valor(-7) || f_archivo_foto(prof.id)
                                                    END,
                           'specialtiesIds'   VALUE pkgcn_perfil_profesional.f_ids_especialidades_usuario(prof.id),
                           'modalidades'      VALUE (
                               SELECT JSON_ARRAYAGG(m.modalidad RETURNING CLOB)
                                  FROM (
                                      SELECT DISTINCT f.id_usuario, NVL(f.modalidad, 'TODAS') AS modalidad
                                        FROM tkr_franjas_profesional f
                                       WHERE f.activo = 1
                                  ) m
                                 WHERE m.id_usuario = prof.id
                           ),
                           'correo'           VALUE prof.correo_electronico,
                           'telefono'         VALUE prof.telefono
                       )
                       RETURNING CLOB
                   ),
                   TO_CLOB('[]')
               )
          INTO v_json_arr
          FROM (
              SELECT u.id,
                     u.usuario,
                     u.id_genero,
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
                     JSON_VALUE(p_json_entrada, '$.id_especialidad') IS NULL 
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_especialidades_usuario ue 
                          WHERE ue.id_usuario = u.id 
                            AND ue.id_especialidad = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_especialidad'))
                     )
                 )
                 AND (
                     JSON_VALUE(p_json_entrada, '$.id_convenio') IS NULL
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_horarios_profesional h
                          WHERE h.id_usuario = u.id
                            AND h.activo = 1
                            AND (h.id_convenio = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio')) OR h.id_convenio IS NULL)
                     )
                 )
                 AND (
                     JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento') IS NULL
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_horarios_profesional h
                          WHERE h.id_usuario = u.id
                            AND h.activo = 1
                            AND (h.id_tipo_aseguramiento = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento')) OR h.id_tipo_aseguramiento IS NULL)
                     )
                 )
                 AND (
                     JSON_VALUE(p_json_entrada, '$.modalidad') IS NULL
                     OR EXISTS (
                         SELECT 1 
                           FROM tkr_franjas_profesional f
                          WHERE f.id_usuario = u.id
                            AND f.activo = 1
                            AND (f.modalidad = UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.modalidad'))) OR f.modalidad IS NULL)
                     )
                 )
                 AND (
                     JSON_VALUE(p_json_entrada, '$.busqueda') IS NULL
                     OR UPPER(u.nombres || ' ' || u.apellidos) LIKE '%' || UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.busqueda'))) || '%'
                     OR UPPER(u.correo_electronico) LIKE '%' || UPPER(TRIM(JSON_VALUE(p_json_entrada, '$.busqueda'))) || '%'
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
    -- Recibe p_json_entrada y evalúa los filtros directamente con JSON_VALUE
    FUNCTION f_consultar_turnos (
        p_json_entrada IN CLOB
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
             WHERE h.id_usuario = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_usuario'))
               AND h.dia_semana = JSON_VALUE(p_json_entrada, '$.dia_semana')
               AND h.activo = 1
               AND (
                   JSON_VALUE(p_json_entrada, '$.id_convenio') IS NULL 
                   OR h.id_convenio = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio')) 
                   OR h.id_convenio IS NULL
               )
               AND (
                   JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento') IS NULL 
                   OR h.id_tipo_aseguramiento = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento')) 
                   OR h.id_tipo_aseguramiento IS NULL
               )
             ORDER BY CASE 
                        WHEN JSON_VALUE(p_json_entrada, '$.id_convenio') IS NOT NULL 
                             AND h.id_convenio = TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio')) 
                        THEN 1 
                        ELSE 2 
                      END,
                      h.hora_desde ASC;

        RETURN v_cursor;
    END f_consultar_turnos;

    -- 3. Consultar catálogos para filtros del directorio (especialidades, convenios, aseguramientos)
    PROCEDURE p_consultar_filtros_catalogo_json (
        p_json_entrada IN  CLOB DEFAULT NULL,
        p_json_salida  OUT CLOB
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

    -- 4. Consultar información detallada del profesional seleccionado
    -- Recibe p_json_entrada y evalúa el filtro del ID con JSON_VALUE
    PROCEDURE p_consultar_detalle_profesional (
        p_json_entrada IN  CLOB,
        p_json_salida  OUT CLOB
    ) IS
    BEGIN
        SELECT JSON_OBJECT(
                   'id'               VALUE u.id,
                   'fullName'         VALUE TRIM(u.nombres || ' ' || u.apellidos),
                   'trabaja_festivos' VALUE NVL(u.trabaja_festivos, 'N'),
                   'slug'             VALUE u.usuario,
                   'gender'           VALUE DECODE(u.id_genero, 1, 'Masculino', 2, 'Femenino', 3, 'Otro', NULL),
                   'rate'             VALUE (
                       SELECT LEAST(ROUND(AVG(ep.satisfacion_medico), 1), 5) 
                         FROM tkr_encuesta_paciente ep,
                              tkr_citas             ct,
                              tkr_cita_usuarios     cu
                        WHERE ep.id_cita            = ct.id
                          AND ct.id                 = cu.id_cita
                          AND cu.id_usuario_atiende = u.id
                        GROUP BY cu.id_usuario_atiende
                   ),
                   'reviews'          VALUE NVL((
                       SELECT COUNT(1) 
                         FROM tkr_encuesta_paciente ep,
                              tkr_citas             ct,
                              tkr_cita_usuarios     cu
                        WHERE ep.id_cita            = ct.id
                          AND ct.id                 = cu.id_cita
                          AND cu.id_usuario_atiende = u.id
                        GROUP BY cu.id_usuario_atiende
                   ), 0),
                   'specialty'        VALUE (
                       SELECT COALESCE(
                                  JSON_ARRAYAGG(
                                      JSON_OBJECT(
                                          'id'                  VALUE e.id,
                                          'nombre_especialidad' VALUE e.nombre_especialidad,
                                          'tipo_especialidad'   VALUE e.tipo_especialidad
                                      )
                                      RETURNING CLOB
                                  ),
                                  TO_CLOB('[]')
                              )
                         FROM tkr_especialidades_usuario eu,
                              tkr_especialidades         e
                        WHERE eu.id_usuario      = u.id
                          AND e.id               = eu.id_especialidad
                   ),
                   'esp_subesp'       VALUE f_nombre_subespecialidades_usuario(u.id),
                   'subspecialty'     VALUE (
                       SELECT sue.subespecialidad
                         FROM tkr_especialidades_usuario eud,
                              tkr_subespecialidad_usu    sue
                        WHERE eud.id_usuario             = u.id
                          AND sue.id_especialidad_usuario = eud.id
                          AND ROWNUM                     = 1
                   ),
                    'days_of_service'  VALUE f_dias_servicio_profesional(
                                             u.id,
                                             COALESCE(JSON_VALUE(p_json_entrada, '$.fecha_inicio'),
                                                      JSON_VALUE(p_json_entrada, '$.fecha_desde'),
                                                      JSON_VALUE(p_json_entrada, '$.fecha_inicial'),
                                                      JSON_VALUE(p_json_entrada, '$.fecha')),
                                             COALESCE(JSON_VALUE(p_json_entrada, '$.fecha_fin'),
                                                      JSON_VALUE(p_json_entrada, '$.fecha_hasta'),
                                                      JSON_VALUE(p_json_entrada, '$.fecha_final')),
                                             TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_convenio')),
                                             TO_NUMBER(JSON_VALUE(p_json_entrada, '$.id_tipo_aseguramiento'))
                                         ),
                   'img_url'          VALUE CASE
                                              WHEN f_archivo_foto(u.id) IS NULL THEN
                                                  pkgca_tkr_parametros.f_consulta_valor(-7) || 'logo_circulo.png'
                                              ELSE
                                                  pkgca_tkr_parametros.f_consulta_valor(-7) || f_archivo_foto(u.id)
                                            END,
                   'specialtiesIds'   VALUE pkgcn_perfil_profesional.f_ids_especialidades_usuario(u.id)
                   RETURNING CLOB
               )
          INTO p_json_salida
          FROM tkr_usuarios u
         WHERE u.id = TO_NUMBER(NVL(JSON_VALUE(p_json_entrada, '$.id_usuario'), JSON_VALUE(p_json_entrada, '$.id')));
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_json_salida := TO_CLOB('{}');
        WHEN OTHERS THEN
            p_json_salida := TO_CLOB('{}');
    END p_consultar_detalle_profesional;

END pkgcn_directorio_profesionales;
/

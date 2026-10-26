CREATE OR REPLACE PACKAGE pkgca_tkr_disponibilidad_bitmap
AS
    /*
          Nombre       : pkgca_tkr_disponibilidad_bitmap
          Descripción  : Paquete de Acceso No-PK y operaciones DML mono-tabla sobre 
                         la tabla tkr_disponibilidad_bitmap.
          Autor        : Orlando Arturo Valverde Quiceno
          e-mail       : vqorlando@gmail.com
          ----------------------------------------------------------------------
          Control de modificaciones
          Fecha        Efectuadas por                     Descripción
          ----------   ---------------   ---------------------------------------
          26/10/2026   OAVQ              1. Creación inicial
          26/10/2026   OAVQ              2. Estandarización a DML mono-tabla con 
                                            parámetro JSON CLOB evaluado con JSON_VALUE
    */

    /*
          Nombre       : p_actualizar_bitmap_ocupado
          Descripción  : Procedimiento DML mono-tabla para actualizar el vector 
                         bitmap_ocupado de la tabla tkr_disponibilidad_bitmap.
                         Recibe un payload JSON (CLOB) evaluado con JSON_VALUE:
                         - id_usuario            : NUMBER (Obligatorio)
                         - fecha                 : VARCHAR2 'YYYY-MM-DD' (Obligatorio)
                         - idx_inicio            : NUMBER (1..288, posición bit inicial)
                         - idx_fin               : NUMBER (1..288, posición bit final)
                         - caracter_bit          : VARCHAR2 ('1' = Ocupado, '0' = Libre)
                         - id_convenio           : NUMBER (Opcional, NULL aplica a todos)
                         - id_tipo_aseguramiento : NUMBER (Opcional, NULL aplica a todos)
                         - modalidad             : VARCHAR2 (Opcional, NULL aplica a todas)
                         
                         Retorna p_filas_afectadas con el número de registros actualizados.
          -----------------------------------------------------------------------
          Control de modificaciones
          Fecha        Efectuadas por                     Descripción
          ----------   ---------------   ----------------------------------------
          26/10/2026   OAVQ              1. Creación
    */
    PROCEDURE p_actualizar_bitmap_ocupado (
        p_json_entrada    IN  CLOB,
        p_filas_afectadas OUT NUMBER
    );

    /*
          Nombre       : f_consultar_x_fecha
          Descripción  : Función para obtener el vector de bitmap de un profesional 
                         en una fecha específica recibiendo payload JSON (CLOB).
          -----------------------------------------------------------------------
          Control de modificaciones
          Fecha        Efectuadas por                     Descripción
          ----------   ---------------   ----------------------------------------
          26/10/2026   OAVQ              1. Creación
    */
    FUNCTION f_consultar_x_fecha (
        p_json_entrada IN CLOB
    ) RETURN SYS_REFCURSOR;

END pkgca_tkr_disponibilidad_bitmap;
/

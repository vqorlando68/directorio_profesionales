# Documentación Funcional: PKGCA_TKR_DISPONIBILIDAD_BITMAP

## 1. Misión del Paquete
Capa de Acceso No-PK y operaciones DML mono-tabla exclusiva sobre la tabla `TKR_DISPONIBILIDAD_BITMAP`. Encapsula la actualización física del vector binario (`bitmap_ocupado`) y la consulta de bitmaps por fecha, recibiendo los parámetros de búsqueda y actualización estructurados en formato JSON (CLOB) y evaluados mediante `JSON_VALUE`.

---

## Método: p_actualizar_bitmap_ocupado

### 1. Descripción Funcional en Lenguaje Natural
Ejecuta la sentencia de actualización física (DML `UPDATE`) sobre los registros de la tabla `tkr_disponibilidad_bitmap` que coincidan con el profesional, la fecha y los filtros opcionales de convenio, aseguramiento y modalidad. Modifica las posiciones binarias entre `idx_inicio` e `idx_fin` colocando el carácter `'1'` (ocupado) o `'0'` (libre). Retorna en el parámetro de salida `p_filas_afectadas` el número de registros actualizados.

### 2. Información que Trae (Lectura / Consultas)
- **Tablas Consultadas:** `tkr_disponibilidad_bitmap` (`b`).
- **Filtros Aplicados:** `b.id_usuario = v_id_usuario AND TRUNC(b.fecha) = TRUNC(v_fecha_dia) AND (filtros opcionales de convenio, aseguramiento y modalidad) FOR UPDATE OF b.bitmap_ocupado`.
- **Datos Retornados:** `p_filas_afectadas OUT NUMBER`.

```json
{
  "id_usuario": 65,
  "fecha": "2026-10-26",
  "idx_inicio": 97,
  "idx_fin": 100,
  "caracter_bit": "1",
  "id_convenio": null,
  "id_tipo_aseguramiento": 1,
  "modalidad": "V"
}
```

### 3. Información que Modifica (Escritura / DML)
- **Tablas Afectadas:** `tkr_disponibilidad_bitmap`.
- **Operación Realizada:** `UPDATE tkr_disponibilidad_bitmap`.
- **Datos Modificados:** Actualiza la cadena binaria `bitmap_ocupado` en el rango de bits especificado y asigna `fecha_actualizacion = SYSTIMESTAMP AT TIME ZONE 'America/Bogota'`.

---

## Método: f_consultar_x_fecha

### 1. Descripción Funcional en Lenguaje Natural
Consulta los registros de vectores de disponibilidad de un profesional para una fecha específica recibiendo un payload JSON evaluado con `JSON_VALUE`.

### 2. Información que Trae (Lectura / Consultas)
- **Tablas Consultadas:** `tkr_disponibilidad_bitmap` (`b`).
- **Filtros Aplicados:** `b.id_usuario = v_id_usuario AND TRUNC(b.fecha) = TO_DATE(v_fecha_str, 'YYYY-MM-DD')`.
- **Datos Retornados:** `SYS_REFCURSOR` con todas las columnas de la tabla ordenadas por aseguramiento y modalidad.

```json
{
  "id_usuario": 65,
  "fecha": "2026-10-26"
}
```

### 3. Información que Modifica (Escritura / DML)
- No realiza operaciones DML.

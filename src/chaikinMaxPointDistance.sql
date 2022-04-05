-- A simple method add points with using function like linemerge, but use exact points 
DROP FUNCTION IF EXISTS chaikinMaxPointDistance(geometry,int);

DROP FUNCTION IF EXISTS chaikinMaxPointDistance(geometry, numeric );

DROP FUNCTION IF EXISTS chaikinMaxPointDistance(
_input_line geometry(LineString),
_utm boolean,
_max_distance numeric 
);

CREATE OR REPLACE FUNCTION chaikinMaxPointDistance(
_input_line geometry(LineString),
_utm boolean, -- to decide how calculate length
_max_distance numeric -- in meter
)
RETURNS geometry(LineString) AS $$
DECLARE
need_to_fix_index_out int[];

--dump_point_list geometry_dump[];
num_points_start int;
num_points_end int;
counter int = 0;
simplfied_line geometry(LineString);

BEGIN



IF (ST_GeometryType(_input_line) != 'ST_LineString' ) THEN
	RAISE EXCEPTION 'Invalid GeometryType(_input_line) %', ST_input_lineetryType(_input_line);
END IF;

 simplfied_line = _input_line;
 
num_points_start =  ST_NumPoints(simplfied_line);

WITH 
 rdb_temp_table AS 
 ( SELECT (dp).path[1] As org_index, (dp).geom As p1,  lead((dp).geom) OVER () AS lead_p
  FROM (
   SELECT ST_DumpPoints(simplfied_line) as dp
  ) as db
 )    

,
 need_to_fix_index AS ( 
   SELECT org_index as index_value,
   CASE WHEN _utm THEN ST_distance(p1, lead_p) 
   ELSE ST_distance(p1, lead_p, true) END AS distance
   FROM rdb_temp_table
 )
select ST_MakeLine(mp) INTO simplfied_line FROM (
 SELECT (ST_DumpPoints(ST_Collect(mp))).geom as mp FROM (
	 select 
	 CASE 
	   	WHEN need_to_fix_index.distance > _max_distance THEN 
	   	array_append(ARRAY[p1],
	   		ST_LineInterpolatePoints(ST_MakeLine(p1, lead_p),_max_distance/need_to_fix_index.distance, true)
	   		)
	
	   	ELSE ARRAY[p1]
	 END as mp
	  from rdb_temp_table, need_to_fix_index
	 where rdb_temp_table.org_index = need_to_fix_index.index_value
	 ) as r
)  as r;



num_points_end = ST_NumPoints(simplfied_line);

RAISE NOTICE ' num_points_start %, num_points_end %  ', num_points_start , num_points_end;

return simplfied_line;
  
END; 
$$ LANGUAGE plpgsql IMMUTABLE ;

--select ST_AsText('0102000020E86400000300000000000000F89023410000000070FD584100000000F89023410000000075FD584100000000109123410000000075FD5841');
--select ST_AsText(chaikinMaxPointDistance('0102000020E86400000300000000000000F89023410000000070FD584100000000F89023410000000075FD584100000000109123410000000075FD5841',true,1000));
--select ST_AsText(chaikinMaxPointDistance('0102000020E86400000300000000000000F89023410000000070FD584100000000F89023410000000075FD584100000000109123410000000075FD5841',true,0.5));
--TODO make tests




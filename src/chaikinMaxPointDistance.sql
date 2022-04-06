-- A simple method add points with using function like linemerge, but use exact points 
DROP FUNCTION IF EXISTS chaikinMaxPointDistance(geometry,int);

DROP FUNCTION IF EXISTS chaikinMaxPointDistance(geometry, numeric );

DROP FUNCTION IF EXISTS chaikinMaxPointDistance(
_input_line geometry(LineString),
_utm boolean,
_max_distance numeric 
);

DROP FUNCTION IF EXISTS chaikinMaxPointDistance(
_input_line geometry(LineString),
_utm boolean,
_max_distance float8 
);

DROP FUNCTION IF EXISTS chaikinMaxPointDistance(
_input_line geometry(LineString),
_utm boolean,
_max_distance integer 
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
max_distance float8 = _max_distance*1.1;

BEGIN



IF (ST_GeometryType(_input_line) != 'ST_LineString' ) THEN
	RAISE EXCEPTION 'Invalid GeometryType(_input_line) %', ST_input_lineetryType(_input_line);
END IF;

 simplfied_line = _input_line;
 
num_points_start =  ST_NumPoints(simplfied_line);

WITH 
 rdb_temp_table AS 
 ( SELECT (dp).path[1] As org_index, (dp).geom As p1,  lead((dp).geom) OVER (order by(dp).path[1]) AS lead_p
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
	  SELECT ST_MakeLine(mp) as mp INTO simplfied_line FROM (
		 SELECT unnest(mp) as mp FROM (
		 select
		 org_index , 
		 CASE 
		   	WHEN need_to_fix_index.distance > max_distance*1.1 THEN 
		   	array_append(ARRAY[p1],
		   		ST_LineInterpolatePoints(ST_MakeLine(p1, lead_p),_max_distance/need_to_fix_index.distance, true)
		   		)
		
		   	ELSE ARRAY[p1]
		 END as mp
		  from rdb_temp_table, need_to_fix_index
		 where rdb_temp_table.org_index = need_to_fix_index.index_value
		 ) as r order by org_index 
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

--select ST_AsText(chaikinMaxPointDistance('0102000020E96400001300000000000000C093EAC000000000EE155A41DDEB4F6DF787EAC037D67010F7155A41DDEB4F6DF787EAC037D67010F7155A41DDEB4F6DF787EAC037D67010F7155A41DDEB4F6DF787EAC037D67010F7155A41DDEB4F6DF787EAC037D67010F7155A41DDEB4F6DF787EAC037D67010F7155A41DDEB4F6DF787EAC037D67010F7155A41DDEB4F6DF787EAC037D67010F7155A41DDEB4F6DF787EAC037D67010F7155A41DDEB4F6DF787EAC037D67010F7155A41D8EB4F6DF787EAC037D67010F7155A41000000009087EAC000000060F7155A41000000003083EAC0000000A0FD155A41000000009082EAC0000000E003165A41000000005081EAC0000000A007165A4100000000707FEAC0000000E008165A4100000000307EEAC0000000C00A165A4100000000407DEAC0000000800E165A41',true,100));



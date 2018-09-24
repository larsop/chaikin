-- A simple method that smooth out line by recducing the angle betwwen line segments

CREATE OR replace FUNCTION chaikinSmoothLineSimple(_geom geometry,_nIterations int default 5 ) 
returns geometry 
AS $$DECLARE 
simplfied_geom GEOMETRY;
num_points int;
counter int = 0;
BEGIN

simplfied_geom := _geom;

-- loop max 5 times
FOR counter IN 1.._nIterations LOOP
 num_points := st_numpoints(simplfied_geom); 
 simplfied_geom := st_linefrommultipoint(mp) FROM ( 
 SELECT st_collect(mp) AS mp 
 FROM ( 
  SELECT unnest(array[p1,p1_n,p2_n,p2]) AS mp 
  FROM ( 
   SELECT 
   CASE 
    WHEN org_index=1 THEN p1 
    ELSE NULL 
   END AS p1, 
   p1_n, 
   p2_n, 
   CASE 
    WHEN org_index=num_points THEN p1 
    ELSE NULL 
   END AS p2 
   FROM ( 
    SELECT org_index, 
    p1, 
    st_lineinterpolatepoint(lp, 0.25) AS p1_n,
    st_lineinterpolatepoint(lp, 0.75) AS p2_n,
    p2 
    FROM ( 
     SELECT r.*, 
     st_makeline(p1, p2) AS lp 
     FROM ( 
      SELECT (dp).path[1] AS org_index,
      (dp).geom AS p1,
      lead((dp).geom) OVER () AS p2
      FROM ( 
       SELECT st_dumppoints(simplfied_geom) AS dp 
       ) AS r 
      ) AS r 
     ) AS r 
    ) AS r 
   ) AS r 
  ) AS r 
 ) AS r;
END LOOP;
 
return simplfied_geom; 
end;
$$ language plpgsql immutable;

--select ST_AsText(chaikinSmoothLineSimple('0102000020E86400000300000000000000F89023410000000070FD584100000000F89023410000000075FD584100000000109123410000000075FD5841'));

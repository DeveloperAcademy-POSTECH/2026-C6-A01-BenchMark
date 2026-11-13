#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdint.h>

typedef struct { float x,y,z,u,v; } Point;
int main(int argc,char** argv){
    FILE *file=fopen(argv[1],"rb");
    if(!file) return 1;
    int n,w,h,tx,ty; float angle,shift,scale;
    if(fread(&n,sizeof(int),1,file)!=1 || fread(&tx,sizeof(int),1,file)!=1 || fread(&ty,sizeof(int),1,file)!=1) return 2;
    w=atoi(argv[3]);h=atoi(argv[4]);angle=atof(argv[5]);shift=atof(argv[6]);scale=atof(argv[7]);
    unsigned char *texture=malloc(tx*ty*3);
    Point *points=malloc(3*n*sizeof(Point));
    if(fread(texture,1,tx*ty*3,file)!=tx*ty*3 || fread(points,sizeof(Point),3*n,file)!=3*n) return 3;
    fclose(file);
    unsigned char *color=calloc(w*h*3,1);
    float *depth=malloc(w*h*sizeof(float));
    for(int i=0;i<w*h;i++) { depth[i]=-1e9f; color[i*3]=235; color[i*3+1]=237; color[i*3+2]=234; }
    float co=cosf(angle),si=sinf(angle);
    for(int i=0;i<3*n;i++) {
        Point *p=points+i;
        float x=co*p->x-si*p->z,z=co*p->z+si*p->x;
        p->x=x*scale+w/2.0f; p->y=(shift-p->y)*scale+h/2.0f; p->z=z;
    }
    for(int i=0;i<n;i++) {
        Point a=points[3*i], b=points[3*i+1], c=points[3*i+2];
        float nx=(b.y-a.y)*(c.z-a.z)-(b.z-a.z)*(c.y-a.y);
        float ny=(b.z-a.z)*(c.x-a.x)-(b.x-a.x)*(c.z-a.z);
        float nz=(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);
        float det=(b.y-c.y)*(a.x-c.x)+(c.x-b.x)*(a.y-c.y);
        if(fabsf(det)<.00001f) continue;
        float normal=sqrtf(nx*nx+ny*ny+nz*nz);
        float shade=.90f+.11f*((.3f*nx-.3f*ny+.80f*fabsf(nz))/normal);
        int x0=fmaxf(0,floorf(fminf(a.x,fminf(b.x,c.x)))), x1=fminf(w-1,ceilf(fmaxf(a.x,fmaxf(b.x,c.x))));
        int y0=fmaxf(0,floorf(fminf(a.y,fminf(b.y,c.y)))), y1=fminf(h-1,ceilf(fmaxf(a.y,fmaxf(b.y,c.y))));
        for(int y=y0;y<=y1;y++) for(int x=x0;x<=x1;x++) {
            float r=((b.y-c.y)*(x+.5f-c.x)+(c.x-b.x)*(y+.5f-c.y))/det;
            float s=((c.y-a.y)*(x+.5f-c.x)+(a.x-c.x)*(y+.5f-c.y))/det, t=1-r-s;
            if(r<0 || s<0 || t<0) continue;
            float z=r*a.z+s*b.z+t*c.z; int j=y*w+x;
            if(z<=depth[j]) continue;
            depth[j]=z;
            float u=r*a.u+s*b.u+t*c.u, v=r*a.v+s*b.v+t*c.v;
            int xi=fminf(tx-1,fmaxf(0,(u-floorf(u))*tx)),yi=fminf(ty-1,fmaxf(0,(1-v+floorf(v))*ty));
            int k=(yi*tx+xi)*3;
            for(int d=0;d<3;d++) color[3*j+d]=(unsigned char)fminf(255,shade*texture[k+d]);
        }
    }
    file=fopen(argv[2],"wb");
    if(!file) return 4;
    fprintf(file,"P6\n%d %d\n255\n",w,h);
    fwrite(color,1,w*h*3,file);
    fclose(file);
    return 0;
}

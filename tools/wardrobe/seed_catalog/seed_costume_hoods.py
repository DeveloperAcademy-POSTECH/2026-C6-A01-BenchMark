"""Per-costume fitting for hoods and the ribbon uniform."""
import numpy as np

import seed_costume_geometry as geometry
from seed_costume_geometry import smoothstep, fit_boots

def options(id):
    # Hood opening and exposed skin colors vary by original material.
    hooded = {'astronaut','astronaut-navy','bee','cat','cat-bear','dinosaur','raincoat'}
    assert id in hooded
    def mask(co,green,rgb,name):
        x,y,z=co.T
        r,g,b=rgb.T
        dark_skin=(g>r+2)&(g>b+4)&(b<95)
        face=(y>.79)&(y<1.32)&(z>.085)&(np.abs(x)<.204)
        eyes=face&(np.abs(x)<.105)&(y>.925)&(y<1.13)&(g<89)&(g>b+1)&(r<70)
        stem_start={'bee':1.286,'cat':1.322,'cat-bear':1.321,'raincoat':1.316}.get(id,1.35)
        stem=(y>stem_start)&(np.abs(x)<.20)&(green|dark_skin)
        if id=='dinosaur':
            # The yellow-green cucumber is brighter than the olive fabric.
            face=(y>.797)&(y<1.27)&(z>.055)&(np.abs(x)<.202)
            light_skin=(g>178)&(r>76)&(g>r*1.19)&(b<90)
            stripe=(g<117)&(g>r*1.55)&(b<55)
            return ~((stem&(y>1.362))|(face&(light_skin|stripe)))
        if id=='bee':
            leg=(y>.136)&(y<.285)&(np.abs(x)>.034)
            center_face=(y>.912)&(y<1.113)&(z>.161)&(np.abs(x)<.105)
            top_stem=stem
            return ~(top_stem|(face&(green|dark_skin|eyes))|center_face|(leg&(green|dark_skin)))
        if id=='raincoat':
            leg=(y>.174)&(y<.322)&(np.abs(x)>.033)
            hand=(y>.43)&(y<.68)&(np.abs(x)>.251)
            return ~(stem|(face&(green|dark_skin|eyes))|((leg|hand)&(green|dark_skin)))
        if id=='cat-bear':
            limb=(y<.13)|((y>.405)&(y<.68)&(np.abs(x)>.265))
            held=(y>.5)&(y<.69)&(z>.10)&(x>.12)
            return ~(stem|(face&(green|dark_skin|eyes))|((limb|held)&(green|dark_skin)))
        if id=='cat':
            limb=(y<.13)|((y>.415)&(y<.655)&(np.abs(x)>.255))
            return ~(stem|(face&(green|dark_skin|eyes))|(limb&(green|dark_skin)))
        hands=(y>.38)&(y<.64)&(np.abs(x)>.28)
        dark_visor=(y>.929)&(y<1.19)&(z>.179)&(np.abs(x)<.11)
        return ~(stem|(face&(green|dark_skin|eyes))|dark_visor|(hands&(green|dark_skin)))

    def fit(p,faces,name):
        x,y,z=p.T.copy()
        if id in ('astronaut','astronaut-navy'):
            p[:,2]=p[:,2]*1.105+.017
            p[:,0]*=1.038
            shoulders=smoothstep((np.abs(x)-.205)/.115) * smoothstep((y-.43)/.115)*(1-smoothstep((y-.69)/.15))
            p[:,1]+=shoulders*.045
            p[:,2]-=shoulders*.018
            # The old crotch opens above the neutral cucumber's lower skin.
            # Close that gap by carrying the inner seam below the seed body.
            inner=(1-smoothstep((np.abs(x)-.012)/.075))
            seam=smoothstep((y-.20)/.13)*(1-smoothstep((y-.385)/.089))
            p[:,1]-=.168*inner*seam
            torso=smoothstep((y-.27)/.09)*(1-smoothstep((y-.495)/.11))
            p[:,2]+=np.sign(z)*.034*torso
            if id=='astronaut-navy':
                # The navy sleeve was cut for an older, lower arm pose.
                p[:,1]+=shoulders*.047
                p[:,0]-=np.sign(x)*shoulders*.019
        elif id=='bee':
            p[:,0]*=1.075
            p[:,2]=p[:,2]*1.06+.020
            arms=smoothstep((np.abs(x)-.21)/.12)*smoothstep((y-.4)/.12)*(1-smoothstep((y-.68)/.16))
            p[:,1]+=arms*.059
            fit_boots(p,x,y,z,.173,source_x=.144,target_x=.134,
                      source_z=.093,target_z=.037,width=1.10,depth=1.14)
        elif id=='dinosaur':
            p[:,0]*=1.025
            p[:,2]=p[:,2]*1.02+.018
        elif id=='raincoat':
            p[:,0]*=1.087
            p[:,2]=p[:,2]*1.14+.011
            skirt=smoothstep((y-.23)/.08)*(1-smoothstep((y-.34)/.14))
            p[:,1]-=.042*skirt
            fit_boots(p,x,y,z,.218,source_x=.134,target_x=.134,
                      source_z=.080,target_z=.027,width=1.14,depth=1.15)
            sleeves=smoothstep((np.abs(x)-.195)/.115)*smoothstep((y-.47)/.12)*(1-smoothstep((y-.70)/.10))
            p[:,2]-=sleeves*.048
            rear=smoothstep((-z-.022)/.082)*smoothstep((y-.46)/.13)*(1-smoothstep((y-.72)/.14))
            p[:,2]-=rear*.026
        else:
            p[:,0]*=1.048
            p[:,2]=p[:,2]*1.07+.018
            arms=smoothstep((np.abs(x)-.215)/.09)*smoothstep((y-.43)/.10)*(1-smoothstep((y-.66)/.15))
            p[:,2]-=arms*.072
            p[:,1]+=arms*.042
            backs=smoothstep((-z-.004)/.090)*smoothstep((np.abs(x)-.173)/.11)
            backs*=smoothstep((y-.55)/.105)*(1-smoothstep((y-.72)/.115))
            p[:,2]-=backs*.025
        # Raise the existing crown (not the face opening) over the body apex.
        hood=smoothstep((y-1.17)/.205)
        p[:,1]+=hood*{'cat':.076,'cat-bear':.076,'bee':.090}.get(id,.050)
        geometry.body.push_out(p,.013)
        return p
    hidden = {
        'astronaut': ('LeftLeg','RightLeg'),
        'astronaut-navy': ('LeftLeg','RightLeg'),
        'bee': ('LeftArm','RightArm'),
        'cat':(),
        'cat-bear': ('RightArm',),
        'dinosaur': ('LeftArm','RightArm','LeftLeg','RightLeg'),
        'raincoat':(),
    }[id]
    return mask,fit,hidden

colors = {
    'bee': (252,204,56),
    'cat': (184,173,172),
    'cat-bear': (184,173,172),
    'raincoat': (252,205,56),
}

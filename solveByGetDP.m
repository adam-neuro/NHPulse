function solveByGetDP(subj,current,sigma,indUse,uniTag,LFtag,extraTissues)
% solveByGetDP(subj,current,sigma,indUse,uniTag,LFtag,extraTissues)
% 
% Solve in getDP, a free FEM solver available at 
% http://getdp.info/
%
% (c) Yu (Andy) Huang, Parra Lab at CCNY
% yhuang16@citymail.cuny.edu
% October 2017
% August 2019 adding lead field

[dirname,subjName] = fileparts(subj);
if isempty(dirname), dirname = pwd; end

load([dirname filesep subjName '_' uniTag '_usedElecArea.mat'],'area_elecNeeded');

if nargin < 7
    extraTissues = [];
end
tissueCfg = roastTissueConfig(extraTissues);
numOfTissue = tissueCfg.numOfTissue;
numOfElec = length(area_elecNeeded);

fid = fopen([dirname filesep subjName '_' uniTag '.pro'],'w');

fprintf(fid,'%s\n\n','Group {');
for i=1:numOfTissue
    fprintf(fid,'%s\n',[tissueCfg.conductivityFields{i} ' = Region[' num2str(i) '];']);
end
% fprintf(fid,'%s\n','gel = Region[7];');
% fprintf(fid,'%s\n','elec = Region[8];');
for i=1:length(indUse)
    fprintf(fid,'%s\n',['gel' num2str(i) ' = Region[' num2str(numOfTissue+indUse(i)) '];']);
end
for i=1:length(indUse)
    fprintf(fid,'%s\n',['elec' num2str(i) ' = Region[' num2str(numOfTissue+numOfElec+indUse(i)) '];']);
end

tissueStr = [];
for i=1:numOfTissue
    tissueStr = [tissueStr tissueCfg.conductivityFields{i} ', '];
end
gelStr = [];
elecStr = [];
usedElecStr = [];
for i=1:length(indUse)
%     fprintf(fid,'%s\n',['usedElec' num2str(i) ' = Region[' num2str(8+i) '];']);
    usedElecStr = [usedElecStr 'usedElec' num2str(i) ', '];
    fprintf(fid,'%s\n',['usedElec' num2str(i) ' = Region[' num2str(numOfTissue+2*numOfElec+indUse(i)) '];']);
    gelStr = [gelStr 'gel' num2str(i) ', '];
    elecStr = [elecStr 'elec' num2str(i) ', '];
end

fprintf(fid,'%s\n',['DomainC = Region[{' tissueStr gelStr elecStr(1:end-2) '}];']);
fprintf(fid,'%s\n\n',['AllDomain = Region[{' tissueStr gelStr elecStr usedElecStr(1:end-2) '}];']);
fprintf(fid,'%s\n\n','}');

fprintf(fid,'%s\n\n','Function {');
for i=1:numOfTissue
    fieldName = tissueCfg.conductivityFields{i};
    fprintf(fid,'%s\n',['sigma[' fieldName '] = ' num2str(sigma.(fieldName)) ';']);
end
% fprintf(fid,'%s\n','sigma[gel] = 0.3;');
% fprintf(fid,'%s\n','sigma[elec] = 5.9e7;');
for i=1:length(indUse)
    fprintf(fid,'%s\n',['sigma[gel' num2str(i) '] = ' num2str(sigma.gel(indUse(i))) ';']);
end
for i=1:length(indUse)
    fprintf(fid,'%s\n',['sigma[elec' num2str(i) '] = ' num2str(sigma.electrode(indUse(i))) ';']);
end

for i=1:length(indUse)
    fprintf(fid,'%s\n',['du_dn' num2str(i) '[] = ' num2str(1000*current(indUse(i))/area_elecNeeded(indUse(i))) ';']);
end

fprintf(fid,'%s\n\n','}');

% fprintf(fid,'%s\n\n','Constraint {');
% fprintf(fid,'%s\n','{ Name ElectricScalarPotential; Type Assign;');
% fprintf(fid,'%s\n','  Case {');
% fprintf(fid,'%s\n','    { Region cathode; Value 0; }');
% fprintf(fid,'%s\n','  }');
% fprintf(fid,'%s\n\n','}');
% fprintf(fid,'%s\n\n','}');

fprintf(fid,'%s\n','Jacobian {');
fprintf(fid,'%s\n','  { Name Vol ;');
fprintf(fid,'%s\n','    Case {');
fprintf(fid,'%s\n','      { Region All ; Jacobian Vol ; }');
fprintf(fid,'%s\n','    }');
fprintf(fid,'%s\n','  }');
fprintf(fid,'%s\n','  { Name Sur ;');
fprintf(fid,'%s\n','    Case {');
fprintf(fid,'%s\n','      { Region All ; Jacobian Sur ; }');
fprintf(fid,'%s\n','    }');
fprintf(fid,'%s\n','  }');
fprintf(fid,'%s\n\n','}');

fprintf(fid,'%s\n','Integration {');
fprintf(fid,'%s\n','  { Name GradGrad ;');
fprintf(fid,'%s\n','    Case { {Type Gauss ;');
fprintf(fid,'%s\n','            Case { { GeoElement Triangle    ; NumberOfPoints  3 ; }');
fprintf(fid,'%s\n','                   { GeoElement Quadrangle  ; NumberOfPoints  4 ; }');
fprintf(fid,'%s\n','                   { GeoElement Tetrahedron ; NumberOfPoints  4 ; }');
fprintf(fid,'%s\n','                   { GeoElement Hexahedron  ; NumberOfPoints  6 ; }');
fprintf(fid,'%s\n','                   { GeoElement Prism       ; NumberOfPoints  9 ; } }');
fprintf(fid,'%s\n','           }');
fprintf(fid,'%s\n','         }');
fprintf(fid,'%s\n','  }');
fprintf(fid,'%s\n\n','}');

fprintf(fid,'%s\n','FunctionSpace {');
fprintf(fid,'%s\n','  { Name Hgrad_v_Ele; Type Form0;');
fprintf(fid,'%s\n','    BasisFunction {');
fprintf(fid,'%s\n','      // v = v  s   ,  for all nodes');
fprintf(fid,'%s\n','      //      n  n');
fprintf(fid,'%s\n','      { Name sn; NameOfCoef vn; Function BF_Node;');
fprintf(fid,'%s\n','        Support AllDomain; Entity NodesOf[ All ]; }');
fprintf(fid,'%s\n','    }');
% fprintf(fid,'%s\n','    Constraint {');
% fprintf(fid,'%s\n','      { NameOfCoef vn; EntityType NodesOf; ');
% fprintf(fid,'%s\n','        NameOfConstraint ElectricScalarPotential; }');
% fprintf(fid,'%s\n','    }');
fprintf(fid,'%s\n','  }');
fprintf(fid,'%s\n\n','}');

fprintf(fid,'%s\n','Formulation {');
fprintf(fid,'%s\n','  { Name Electrostatics_v; Type FemEquation;');
fprintf(fid,'%s\n','    Quantity {');
fprintf(fid,'%s\n','      { Name v; Type Local; NameOfSpace Hgrad_v_Ele; }');
fprintf(fid,'%s\n','    }');
fprintf(fid,'%s\n','    Equation {');
fprintf(fid,'%s\n','      Galerkin { [ sigma[] * Dof{d v} , {d v} ]; In DomainC; ');
fprintf(fid,'%s\n\n','                 Jacobian Vol; Integration GradGrad; }');

for i=1:length(indUse)
    
    fprintf(fid,'%s\n',['      Galerkin{ [ -du_dn' num2str(i) '[], {v} ]; In usedElec' num2str(i) ';']);
    fprintf(fid,'%s\n','                 Jacobian Sur; Integration GradGrad;}');
    
end

fprintf(fid,'%s\n','    }');
fprintf(fid,'%s\n','  }');
fprintf(fid,'%s\n\n','}');

fprintf(fid,'%s\n','Resolution {');
fprintf(fid,'%s\n','  { Name EleSta_v;');
fprintf(fid,'%s\n','    System {');
fprintf(fid,'%s\n','      { Name Sys_Ele; NameOfFormulation Electrostatics_v; }');
fprintf(fid,'%s\n','    }');
fprintf(fid,'%s\n','    Operation { ');
fprintf(fid,'%s\n','      Generate[Sys_Ele]; Solve[Sys_Ele]; SaveSolution[Sys_Ele];');
fprintf(fid,'%s\n','    }');
fprintf(fid,'%s\n','  }');
fprintf(fid,'%s\n\n','}');

fprintf(fid,'%s\n','PostProcessing {');
fprintf(fid,'%s\n','  { Name EleSta_v; NameOfFormulation Electrostatics_v;');
fprintf(fid,'%s\n','    Quantity {');
fprintf(fid,'%s\n','      { Name v; ');
fprintf(fid,'%s\n','        Value { ');
fprintf(fid,'%s\n','          Local { [ {v} ]; In AllDomain; Jacobian Vol; } ');
fprintf(fid,'%s\n','        }');
fprintf(fid,'%s\n','      }');
fprintf(fid,'%s\n','      { Name e; ');
fprintf(fid,'%s\n','        Value { ');
fprintf(fid,'%s\n','          Local { [ -{d v} ]; In AllDomain; Jacobian Vol; }');
fprintf(fid,'%s\n','        }');
fprintf(fid,'%s\n','      }');
fprintf(fid,'%s\n','    }');
fprintf(fid,'%s\n','  }');
fprintf(fid,'%s\n','}');

fprintf(fid,'%s\n\n','PostOperation {');
fprintf(fid,'%s\n','{ Name Map; NameOfPostProcessing EleSta_v;');
fprintf(fid,'%s\n','   Operation {');
if isempty(LFtag)
    fprintf(fid,'%s\n',['     Print [ v, OnElementsOf DomainC, File "' subjName '_' uniTag '_v.pos", Format NodeTable ];']);
end
fprintf(fid,'%s\n',['     Print [ e, OnElementsOf DomainC, Smoothing, File "' subjName '_' uniTag '_e' LFtag '.pos", Format NodeTable ];']);
fprintf(fid,'%s\n','   }');
fprintf(fid,'%s\n\n','}');
fprintf(fid,'%s\n','}');

fclose(fid);

roastRoot = fileparts(mfilename('fullpath'));
str = computer('arch');
switch str
    case 'win64'
        solverName = 'getdp.exe';
    case 'glnxa64'
        solverName = 'getdp';
    case {'maci64', 'maca64'}
        solverName = 'getdpMac';
    otherwise
        error('Unsupported operating system!');
end
solverPath = fullfile(roastRoot, 'lib', 'getdp-3.2.0', 'bin', solverName);
if exist(solverPath, 'file') ~= 2
    error('GetDP solver not found: %s', solverPath);
end

% cmd = [fileparts(which(mfilename)) filesep solverPath ' '...
%     fileparts(which(mfilename)) filesep dirname filesep subjName '_' uniTag '.pro -solve EleSta_v -msh '...
%     fileparts(which(mfilename)) filesep dirname filesep subjName '_' uniTag '_ready.msh -pos Map'];
cmd = ['"' solverPath '" "' subjName '_' uniTag '.pro" -solve EleSta_v -msh "' ...
    subjName '_' uniTag '_ready.msh" -pos Map'];
oldDir = pwd;
dirCleanup = onCleanup(@() cd(oldDir)); %#ok<NASGU>
cd(dirname);
try
    status = system(cmd);
catch solverException
    error('GetDP solver launch failed: %s', solverException.message);
end

if status
    error('getDP solver cannot work properly on your system. Please check any error message you got.');
else % after solving, delete intermediate files
    delete([dirname filesep subjName '_' uniTag '.pre']);
    delete([dirname filesep subjName '_' uniTag '.res']);
end
